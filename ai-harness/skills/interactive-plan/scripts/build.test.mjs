import assert from "node:assert/strict";
import { test } from "node:test";
import os from "node:os";
import path from "node:path";
import { assemble, buildPage } from "./build.mjs";

const data = {
  artifactId: "t",
  revision: "1",
  kind: "exploration",
  title: "T",
  pages: [{ id: "p", title: "P", html: "<p>x</p>" }],
};

test("page CSS uses its own scope outside the frame content scope", async () => {
  const html = await buildPage(path.join(os.tmpdir(), "page.json"), {
    artifactId: "t",
    revision: "1",
    kind: "exploration",
    title: "T",
    page: { id: "p", title: "P", html: "<p>x</p>", cssText: "p{color:red}" },
  });
  const style = html.slice(html.indexOf("<style>"), html.indexOf("</style>"));
  assert.match(style, /@layer frame, plan, components;/);
  assert.match(
    style,
    /@layer plan \{\n@scope \(#page-content\[data-page-id="p"\]\[data-revision="1"\]\) \{ p\{color:red\} \}/,
  );
  assert.ok(
    style.indexOf(
      '@scope (#page-content[data-page-id="p"][data-revision="1"])',
    ) < style.indexOf("@scope (#page-content)"),
  );
});

// The cascade ranks an unlayered rule above every layered one, so an
// unlayered frame.css would outrank both other layers.
test("frame CSS is layered, and the component layer comes last", async () => {
  const html = await assemble(data);
  const style = html.slice(html.indexOf("<style>"), html.indexOf("</style>"));
  assert.match(style, /@layer frame \{\n:root \{/);
  assert.ok(
    style.indexOf("@layer plan {") < style.indexOf("@layer components {"),
    "the plan layer is written before the component layer",
  );
});

test("a component's styles and behavior are bundled", async () => {
  const html = await assemble(data);
  assert.match(html, /\/\* components\/question\/styles\.css \*\//);
  assert.match(html, /\/\* components\/question\/behavior\.mjs \*\//);
  assert.match(html, /planUI\.define\("question"/);
});

// A plan's script runs after the frame's module, so planUI.define is
// available to it before the first page renders.
test("the plan's script is the last module in the document", async () => {
  const html = await assemble(data, { js: 'planUI.define("mine", {});' });
  const modules = html.split('<script type="module">').slice(1);
  assert.equal(modules.length, 2, "the frame's module and the plan's");
  assert.match(modules[0], /planUI\.define\("question"/);
  assert.match(modules[1], /^\nplanUI\.define\("mine", \{\}\);\n<\/script>/);
});

test("a closing style tag in plan CSS is refused", async () => {
  await assert.rejects(
    assemble(data, { css: "</style><script>1</script>" }),
    /closing style/,
  );
});

test("page JavaScript cannot restyle the frame", async () => {
  await assert.rejects(
    buildPage(path.join(os.tmpdir(), "page.json"), {
      artifactId: "t",
      revision: "1",
      kind: "exploration",
      title: "T",
      page: {
        id: "p",
        title: "P",
        html: "<p>x</p>",
        jsText:
          "export function setup() { document.body.style.color = 'red'; }",
      },
    }),
    /restyles document\.body/,
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

test("an option label of exactly 24 characters is accepted", async () => {
  const long = "x".repeat(24);
  const html = await assemble(
    page(
      decision(
        `<button data-value="a" data-label="${long}">a</button>${option("b")}`,
      ),
    ),
  );
  assert.match(html, /x{24}/);
});

// The rule is "no h1", not "no repeated words".
test("a page may repeat its title in a lower heading", async () => {
  await assert.doesNotReject(assemble(page("<h2>P</h2><p>x</p>")));
});

test("a group's label is not held to the option limit", async () => {
  const html = await assemble(
    page(
      `<section data-choice="d" data-label="${"y".repeat(60)}">${option()}${option("b")}</section>`,
    ),
  );
  assert.match(html, /y{60}/);
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
    page(
      decision(
        `<button data-value="a" data-label="${"x".repeat(25)}">a</button>${option("b")}`,
      ),
    ),
    /^page "p": option label "x{25}" is 25 characters, over 24$/m,
  );
  await refused(
    page("<h1>P</h1><p>x</p>"),
    /^page "p": the frame draws the page title, so a page has no h1$/m,
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
    page(`<pre data-language="diff">- a\n+ b</pre>`),
    /^page "p": a code block marked diff belongs in before-after\. Run node components\/before-after\/diff\.mjs BEFORE AFTER OUT\.json$/m,
  );
  await refused(
    page(
      `<fieldset data-multiselect="s" data-label="S"><label><input type="checkbox" data-value="a" checked> A</label></fieldset>`,
    ),
    /^page "p": checklist "s" has a checked box\. Start every box unchecked\.$/m,
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

test("an Agreed page opens with a task, and the plan data carries it", async () => {
  const agreed = (page) =>
    buildPage(path.join(os.tmpdir(), "agreed.json"), {
      artifactId: "t",
      revision: "1",
      kind: "exploration",
      title: "T",
      page: { id: "agreed", title: "Agreed so far", agreements: [], ...page },
    });
  await assert.rejects(
    agreed({}),
    /page "agreed": Agreed has no task\. State what the plan is building towards\./,
  );
  await assert.rejects(
    agreed({ task: { title: " ", html: "<p>x</p>" } }),
    /page "agreed": the task has no title/,
  );
  const task = { title: "Retries", html: "<p>Checkout retries once.</p>" };
  const html = await agreed({ task });
  const data = JSON.parse(
    html
      .match(/id="plan-data">([\s\S]*?)<\/script>/)[1]
      .replaceAll("\\u003c", "<"),
  );
  assert.deepEqual(data.task, task);
});
