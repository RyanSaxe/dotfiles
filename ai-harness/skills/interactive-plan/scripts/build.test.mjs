import assert from "node:assert/strict";
import { test } from "node:test";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { assemble, build } from "./build.mjs";

const data = {
  artifactId: "t",
  revision: "1",
  kind: "exploration",
  title: "T",
  pages: [{ id: "p", title: "P", html: "<p>x</p>" }],
};

test("plan CSS is scoped to the page content", async () => {
  const html = await assemble(data, { css: "body{background:red}" });
  assert.match(
    html,
    /@scope \(#page-content\) \{\nbody\{background:red\}\n\}\n<\/style>/,
  );
});

test("a closing style tag in plan CSS is refused", async () => {
  await assert.rejects(
    assemble(data, { css: "</style><script>1</script>" }),
    /closing style/,
  );
});

const page = (html, extra = {}) => ({
  ...data,
  pages: [{ id: "p", title: "P", html }],
  ...extra,
});
const decision = (options) =>
  `<section data-choice="d" data-label="D">${options}</section>`;
const option = (value = "a") =>
  `<button data-value="${value}" data-label="${value}">${value}</button>`;
const refused = (plan, message, js) =>
  assert.rejects(assemble(plan, { js }), (error) => {
    assert.match(error.message, message);
    return true;
  });

test("the build refuses each structural problem and names it", async () => {
  await refused(
    { ...data, pages: [data.pages[0], data.pages[0]] },
    /^page "p" appears twice$/m,
  );
  await refused(
    page(decision(option() + option("b")) + decision(option() + option("b"))),
    /^page "p": control "d" appears twice$/m,
  );
  await refused(
    page(`<section data-choice="d">${option()}${option("b")}</section>`),
    /^page "p": control "d" has no data-label$/m,
  );
  await refused(
    page(decision(option() + `<button data-value="">x</button>`)),
    /^page "p": an option in "d" has no data-value$/m,
  );
  await refused(
    page(decision(option())),
    /^page "p": decision "d" has 1 option$/m,
  );
  await refused(
    page(`<section data-question="q" data-label="Q"><h3>?</h3></section>`),
    /^page "p": question "q" has no textarea$/m,
  );
  await refused(
    page("<pre>x</pre>"),
    /^page "p": a code block has no data-language$/m,
  );
  await refused(
    page(`<div data-file="a.ts">x</div>`),
    /^page "p": a code block has no data-language$/m,
  );
  await refused(
    page(`<textarea data-diff-input hidden>{"before":""}</textarea>`),
    /^page "p": a diff input is not JSON with before, after and patch$/m,
  );
  await refused(
    page(`<a href="#nope">x</a>`),
    /^page "p": link "#nope" names no page$/m,
  );
  await refused(
    page(`<div data-prototype="ghost"></div>`),
    /^page "p": prototype "ghost" does not exist$/m,
  );
  await refused(
    data,
    /^plan\.js line 2 restyles document\.body$/m,
    "1;\ndocument.body.style.background = 'red';",
  );
});

test("well-formed controls, anchors and blocks pass", async () => {
  const html = await assemble(
    page(
      decision(option() + option("b")) +
        `<section data-question="q" data-label="Q"><textarea></textarea></section>` +
        `<div data-language="ts" data-file="a.ts">x</div><pre data-diff-source="before"></pre>` +
        `<a href="#p">p</a><a href="#agreed">a</a><a href="#local">l</a><i id="local"></i>` +
        `<div data-prototype="demo"></div>` +
        `<textarea data-diff-input hidden>{"before":"a","after":"b","patch":"p"}</textarea>`,
      {
        prototypes: [
          { id: "demo", title: "Demo", html: "<p>d</p>", height: 100 },
        ],
      },
    ),
    { js: "const wide = document.body.clientWidth > 900;" },
  );
  assert.match(html, /id="plan-data"/);
});

test("the component fixture builds", async (t) => {
  const here = path.dirname(fileURLToPath(import.meta.url));
  const work = await fs.mkdtemp(path.join(os.tmpdir(), "plan-fixture-"));
  t.after(() => fs.rm(work, { recursive: true, force: true }));
  for (const entry of await fs.readdir(path.join(here, "fixture")))
    await fs.copyFile(
      path.join(here, "fixture", entry),
      path.join(work, entry),
    );
  await fs.writeFile(path.join(work, "fixture.css"), "");
  await fs.writeFile(path.join(work, "fixture.js"), "");
  const html = await build(path.join(work, "fixture.json"));
  assert.match(html, /id="plan-data"/);
});
