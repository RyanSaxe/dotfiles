import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";
import test from "node:test";
import {
  assemble,
  build,
  excerptRows,
  fillExcerpts,
} from "../../ai-harness/skills/visual-review/scripts/build.mjs";
import {
  check,
  diagramFacts,
  styledClasses,
} from "../../ai-harness/skills/visual-review/scripts/check.mjs";

const exec = promisify(execFile);
const skill = fileURLToPath(
  new URL("../../ai-harness/skills/visual-review/", import.meta.url),
);
const frameCss = await fs.readFile(
  path.join(skill, "assets/frame.css"),
  "utf8",
);

const SOURCE = [
  "export function focal(p, gamma) {",
  "  const focus = (1 - p) ** gamma;",
  "  return -focus * Math.log(p);",
  "}",
  "",
  "export const DEFAULT_GAMMA = 2;",
].join("\n");

/** A repository with one committed file, and a document beside it. */
async function repository(t, overrides = {}) {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), "vr-"));
  t.after(() => fs.rm(root, { recursive: true, force: true }));
  const repo = path.join(root, "repo");
  await fs.mkdir(path.join(repo, "src"), { recursive: true });
  await fs.writeFile(path.join(repo, "src/focal.js"), SOURCE + "\n");
  // The fixture's commits must land in the fixture. A hook or a rebase
  // exports GIT_DIR to the checks it runs, which would point these commands
  // at the repository running the suite; and they are not gated work, so
  // they bypass whatever hooks that repository's config names.
  const env = { ...process.env };
  for (const key of ["GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE"])
    delete env[key];
  const git = (...args) =>
    exec("git", ["-c", "core.hooksPath=/dev/null", ...args], {
      cwd: repo,
      env,
    });
  await git("init", "-q");
  await git("config", "user.email", "t@example.com");
  await git("config", "user.name", "t");
  await git("add", ".");
  await git("commit", "-q", "--no-verify", "-m", "one");
  const docs = path.join(root, "docs");
  await fs.mkdir(docs);
  const pages = overrides.pages ?? [
    {
      id: "loss",
      title: "The loss",
      html:
        "<p>Two lines matter.</p>" +
        '<figure class="excerpt" data-file="src/focal.js" data-lines="2-3" data-language="javascript">' +
        '<ol class="notes"><li data-line="3" data-span="2-3"><b>Why</b> The focus term.</li></ol></figure>',
    },
    { id: "gamma", title: "Gamma", html: "<p>The default.</p>", depth: 1 },
  ];
  const description = {
    documentId: "focal",
    title: "Focal loss",
    subtitle: "one file",
    lede: "One paragraph.",
    repository: "../repo",
    pages,
    ...overrides.description,
  };
  if (overrides.opens !== undefined) {
    await fs.writeFile(path.join(docs, "opens.mmd"), overrides.opens);
    description.opens = "opens.mmd";
  }
  if (overrides.css !== undefined) {
    await fs.writeFile(path.join(docs, "doc.css"), overrides.css);
    description.css = "doc.css";
  }
  const source = path.join(docs, "document.json");
  await fs.writeFile(source, JSON.stringify(description));
  return { root, repo, docs, source };
}

test("a build is one file holding every page, with the excerpt's lines read from the repository", async (t) => {
  const { source } = await repository(t);
  const html = await build(source);
  assert.match(html, /Two lines matter\./);
  assert.match(html, /The default\./);
  // The rows are the file's lines at the commit, numbered as the file numbers them.
  assert.match(
    html,
    /data-line=\\"2\\"[^]*?const focus = \(1 - p\) \*\* gamma;/,
  );
  assert.match(html, /data-line=\\"3\\"[^]*?return -focus \* Math\.log\(p\);/);
  assert.doesNotMatch(html, /data-line=\\"4\\"/);
  assert.match(html, /"commit":"[0-9a-f]{40}"/);
  assert.match(html, /"ref":"HEAD"/);
  assert.match(html, /<title>Focal loss<\/title>/);
});

test("the command rebuilds over its own output and refuses a file it did not write", async (t) => {
  const { source, docs } = await repository(t);
  const cli = path.join(skill, "scripts/build.mjs");
  const output = path.join(docs, "out.html");
  await exec("node", [cli, source, output]);
  await exec("node", [cli, source, output]);
  assert.match(await fs.readFile(output, "utf8"), /Two lines matter\./);
  const other = path.join(docs, "notes.html");
  await fs.writeFile(other, "<p>mine</p>");
  await assert.rejects(
    exec("node", [cli, source, other]),
    /not a document this builder wrote/,
  );
  assert.equal(await fs.readFile(other, "utf8"), "<p>mine</p>");
});

test("a note outside its excerpt fails the build", async (t) => {
  const note = await repository(t, {
    pages: [
      {
        id: "a",
        title: "A",
        html: '<figure class="excerpt" data-file="src/focal.js" data-lines="2-3" data-language="javascript"><ol class="notes"><li data-line="9">x</li></ol></figure>',
      },
    ],
  });
  await assert.rejects(
    build(note.source),
    /note on line 9 is outside lines 2-3/,
  );
});

test("a diagram file that is not there is refused in the build's own form", async (t) => {
  const missing = await repository(t, {
    pages: [
      {
        id: "a",
        title: "A",
        html: '<div data-diagram data-file="gone.mmd"></div>',
      },
    ],
  });
  await assert.rejects(
    build(missing.source),
    /^Error: The document was not built:\n {2}gone\.mmd is not beside the description$/,
  );
});

test("a build outside any repository says so", async (t) => {
  const nowhere = await repository(t, {
    description: { repository: "../nowhere" },
  });
  await fs.mkdir(path.join(nowhere.root, "nowhere"));
  await assert.rejects(
    build(nowhere.source),
    /not built:\n {2}.*nowhere is not inside a repository/,
  );
});

test("lines past the end of the file, and a file the commit does not have, fail the build", async (t) => {
  const past = await repository(t, {
    pages: [
      {
        id: "a",
        title: "A",
        html: '<figure class="excerpt" data-file="src/focal.js" data-lines="5-9" data-language="javascript"></figure>',
      },
    ],
  });
  await assert.rejects(
    build(past.source),
    /run past the end of the file \(6 lines\)/,
  );
  const missing = await repository(t, {
    pages: [
      {
        id: "a",
        title: "A",
        html: '<figure class="excerpt" data-file="src/nope.js" data-lines="1-2" data-language="javascript"></figure>',
      },
    ],
  });
  await assert.rejects(
    build(missing.source),
    /src\/nope\.js does not exist at/,
  );
});

test("a label class nothing styles, and a mark on a node that does not exist, fail the build; an invented class with its own stylesheet does not", async (t) => {
  const unstyled = await repository(t, {
    opens:
      "flowchart LR\n  a[\"<span class='titel'>x</span>\"] --> b\n  class a marked\n",
  });
  await assert.rejects(
    build(unstyled.source),
    /label class "titel" is styled by nothing/,
  );
  const ghost = await repository(t, {
    opens: "flowchart LR\n  a --> b\n  class a,c marked\n",
  });
  await assert.rejects(build(ghost.source), /"c" is marked but is not a node/);
  const invented = await repository(t, {
    opens: "flowchart LR\n  a[\"<span class='owner'>x</span>\"] --> b\n",
    css: ".owner { color: var(--accent) !important; }",
  });
  await build(invented.source);
});

test("a document stylesheet with a colour that is not a token fails the build", async (t) => {
  const { source } = await repository(t, { css: ".x { color: #ff0000; }" });
  await assert.rejects(build(source), /colour that is not a token/);
});

test("the frame carries nothing that collects feedback or talks to a hub", async () => {
  const html = await assemble({
    documentId: "d",
    title: "D",
    pages: [{ id: "p", title: "P", html: "<p>x</p>" }],
  });
  for (const word of [
    "submit",
    "Agreed",
    "sessionId",
    "/api/",
    "working-card",
    "data-choice",
  ])
    assert.ok(!html.includes(word), `frame contains ${word}`);
  for (const pin of [
    "mermaid@11.12.0",
    "layout-elk@0.2.3",
    "shiki@3.12.2",
    "katex@0.16.22",
  ])
    assert.ok(html.includes(pin), `frame does not pin ${pin}`);
});

test("diagram facts: node ids come from declarations and edges, classes from labels and marks", () => {
  const facts = diagramFacts(
    "flowchart LR\n  subgraph s [S]\n    a[\"<span class='title'>A</span><span class='path'>p</span>\"] --> b\n  end\n  b -- polled --> c((C))\n  d\n  class a,b marked\n",
  );
  assert.deepEqual([...facts.nodes].sort(), ["a", "b", "c", "d", "s"]);
  assert.deepEqual([...facts.classes].sort(), ["path", "title"]);
  assert.deepEqual(facts.marks, [{ ids: ["a", "b"], name: "marked" }]);
  assert.ok(styledClasses(frameCss).has("marked"));
  assert.ok(styledClasses(frameCss).has("delta"));
});

test("excerpt rows escape the code they carry and number from the requested line", () => {
  const rows = excerptRows("a < b\n<script>\nc\n", 2, 3);
  assert.match(rows, /data-line="2"[^]*?&lt;script&gt;/);
  assert.match(rows, /data-line="3"[^]*?>c</);
  assert.doesNotMatch(rows, /data-line="1"/);
});

test("check reports every problem at once rather than the first", async (t) => {
  const { source } = await repository(t);
  const problems = await check(
    {
      documentId: "bad id",
      title: "",
      pages: [
        { id: "a", title: "A", html: "" },
        { id: "a", title: "B", html: "" },
      ],
    },
    { frameCss, cwd: path.dirname(source) },
  );
  assert.ok(problems.length >= 3, problems.join("\n"));
  assert.ok(problems.some((p) => /documentId/.test(p)));
  assert.ok(problems.some((p) => /title is required/.test(p)));
  assert.ok(problems.some((p) => /used twice/.test(p)));
});

test("fillExcerpts leaves a page without excerpts untouched", async (t) => {
  const { repo } = await repository(t);
  const { stdout } = await exec("git", ["rev-parse", "HEAD"], { cwd: repo });
  const html = "<p>nothing to fill</p>";
  assert.equal(await fillExcerpts(html, stdout.trim(), repo), html);
});

test("a diagram named by data-file arrives in the page as text; raw label markup inline fails the build", async (t) => {
  const filed = await repository(t, {
    pages: [
      {
        id: "a",
        title: "A",
        html: '<div data-diagram data-file="d.mmd"></div>',
      },
    ],
  });
  await fs.writeFile(
    path.join(filed.docs, "d.mmd"),
    "flowchart LR\n  a[\"<span class='title'>A</span>\"] --> b\n",
  );
  const html = await build(filed.source);
  // Escaped in the page, so Mermaid reads the span as part of its source.
  assert.match(html, /&lt;span class='title'&gt;A&lt;\/span&gt;/);
  const inline = await repository(t, {
    pages: [
      {
        id: "a",
        title: "A",
        html: "<div data-diagram>flowchart LR\n  a[\"<span class='title'>A</span>\"] --> b\n</div>",
      },
    ],
  });
  await assert.rejects(build(inline.source), /raw markup/);
});
