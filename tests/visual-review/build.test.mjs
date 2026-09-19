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
} from "../../ai-harness/skills/visual-review/scripts/build.mjs";
import { check } from "../../ai-harness/skills/visual-review/scripts/check.mjs";

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
      html: "<p>Two lines matter.</p>",
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
  const source = path.join(docs, "document.json");
  await fs.writeFile(source, JSON.stringify(description));
  return { root, repo, docs, source };
}

test("a build is one file holding every page, with the excerpt's lines read from the repository", async (t) => {
  const { source } = await repository(t);
  const html = await build(source);
  assert.match(html, /Two lines matter\./);
  assert.match(html, /The default\./);
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
  for (const pin of ["shiki@3.12.2"])
    assert.ok(html.includes(pin), `frame does not pin ${pin}`);
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
