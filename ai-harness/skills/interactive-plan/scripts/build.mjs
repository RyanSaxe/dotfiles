#!/usr/bin/env node
import { realpathSync } from "node:fs";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { artifactData, pagePlan, validPage } from "./session.mjs";

const assets = new URL("../assets/", import.meta.url);
/** Where a user keeps components of their own, outside the skill. The skill
    is installed and updated as a unit, so a component written into its own
    directory would be an edit to installed software. */
export function userComponents(env = process.env) {
  const home = env.XDG_CONFIG_HOME || path.join(os.homedir(), ".config");
  return path.join(home, "interactive-plan", "components");
}

const componentRoots = () => [
  fileURLToPath(new URL("../components/", import.meta.url)),
  userComponents(),
];

/** The component directories, sorted, so registration order is fixed. */
async function componentNames(root) {
  const entries = await fs
    .readdir(root, { withFileTypes: true })
    .catch(() => []);
  return entries
    .filter((entry) => entry.isDirectory())
    .map((entry) => entry.name)
    .sort();
}

/** Every component, by name. A name in a later root replaces the same name
    in an earlier one, which is how a user changes a shipped component
    without forking the skill. A root that does not exist contributes none. */
export async function componentDirectories(roots = componentRoots()) {
  const found = new Map();
  for (const [index, root] of roots.entries())
    for (const name of await componentNames(root))
      found.set(name, { name, directory: path.join(root, name), root: index });
  return [...found.values()].sort((a, b) => (a.name < b.name ? -1 : 1));
}

/** One named file from every component that has it, in name order. A
    component that ships no behavior, or no styles, is skipped rather than
    contributing an empty part. */
async function componentParts(roots, file, wrap) {
  const found = await componentDirectories(roots);
  const parts = await Promise.all(
    found.map(async ({ name, directory, root }) => {
      const text = await fs
        .readFile(path.join(directory, file), "utf8")
        .catch(() => "");
      const from = root === 0 ? `components/${name}` : `${name} (yours)`;
      return text.trim() ? wrap(`${from}/${file}`, text.trim()) : "";
    }),
  );
  return parts.filter(Boolean).join("\n");
}

const componentStyles = (roots) =>
  componentParts(roots, "styles.css", (at, text) => `/* ${at} */\n${text}`);

/* Each behavior is evaluated in a block, so what a component declares at the
   top of its file stays inside it and two components cannot collide over a
   name. The frame's own helpers stay in scope, because the block is inside
   the frame's module. */
const componentBehaviors = (roots) =>
  componentParts(
    roots,
    "behavior.mjs",
    (at, text) => `/* ${at} */\n{\n${text}\n}`,
  );

const attribute = (tag, name) => {
  const match = tag.match(new RegExp(`\\s${name}=(?:"([^"]*)"|'([^']*)')`));
  return match ? (match[1] ?? match[2]) : undefined;
};
const controlKinds = ["data-choice", "data-multiselect", "data-question"];

const labelLimit = 24;

/** Structural problems in the assembled pages and the plan's script. */
export function problems(data, js = "", { allowUnknownPages = false } = {}) {
  const list = [];
  const pageIds = new Set();
  for (const page of data.pages) {
    if (pageIds.has(page.id)) list.push(`page "${page.id}" appears twice`);
    pageIds.add(page.id);
  }
  const targets = new Set([...pageIds, "agreed", "feedback"]);
  const prototypes = new Set((data.prototypes || []).map((item) => item.id));
  for (const page of data.pages) {
    const html = page.html || "";
    const at = `page "${page.id}"`;
    const tags = html.match(/<[a-zA-Z][^>]*>/g) || [];
    const controls = new Set();
    for (const tag of tags) {
      for (const kind of controlKinds) {
        const id = attribute(tag, kind);
        if (id === undefined) continue;
        if (controls.has(id)) list.push(`${at}: control "${id}" appears twice`);
        controls.add(id);
        if (!attribute(tag, "data-label"))
          list.push(`${at}: control "${id}" has no data-label`);
      }
      // The tab strip shares its width between the option labels, so a long
      // one leaves nothing for the rest. Only the label a tab shows is
      // bounded; the option's own header keeps its wording, and a group's
      // label is read on Agreed and on Feedback, never in a strip.
      const label = attribute(tag, "data-label");
      if (
        label !== undefined &&
        attribute(tag, "data-value") !== undefined &&
        label.length > labelLimit
      )
        list.push(
          `${at}: option label "${label}" is ${label.length} characters, over ${labelLimit}`,
        );
      // The frame draws the page title as the page's only h1, so a second
      // one is always a duplicate heading, whatever it says.
      if (/^<h1[\s>]/i.test(tag))
        list.push(`${at}: the frame draws the page title, so a page has no h1`);
      if (/^<pre\b/i.test(tag) || /^<div\b/i.test(tag)) {
        const named = attribute(tag, "data-file") !== undefined;
        const source = attribute(tag, "data-diff-source") !== undefined;
        if (
          (/^<pre\b/i.test(tag) || named) &&
          !source &&
          !attribute(tag, "data-language")
        )
          list.push(`${at}: a code block has no data-language`);
      }
      const link = attribute(tag, "href");
      if (
        link?.startsWith("#") &&
        !targets.has(link.slice(1)) &&
        !allowUnknownPages
      )
        if (!new RegExp(`\\sid="${link.slice(1)}"`).test(html))
          list.push(`${at}: link "${link}" names no page`);
      const prototype = attribute(tag, "data-prototype");
      if (prototype !== undefined && !prototypes.has(prototype))
        list.push(`${at}: prototype "${prototype}" does not exist`);
    }
    // Each control's options run from its tag to the next control's tag.
    const parts = html.split(
      /(?=<[a-zA-Z][^>]*\sdata-(?:choice|multiselect|question)=)/,
    );
    for (const part of parts) {
      const tag = part.match(/^<[a-zA-Z][^>]*>/)?.[0];
      if (!tag) continue;
      const kind = controlKinds.find(
        (name) => attribute(tag, name) !== undefined,
      );
      const id = attribute(tag, kind);
      const options =
        part.match(/<[a-zA-Z][^>]*\sdata-value(?:=|\s|>)[^>]*>/g) || [];
      for (const option of options)
        if (!attribute(option, "data-value"))
          list.push(`${at}: an option in "${id}" has no data-value`);
      if (kind === "data-choice" && options.length < 2)
        list.push(
          `${at}: decision "${id}" has ${options.length} option${options.length === 1 ? "" : "s"}`,
        );
      if (kind === "data-question" && !/<textarea\b/i.test(part))
        list.push(`${at}: question "${id}" has no textarea`);
    }
    for (const input of html.match(
      /<textarea[^>]*\sdata-diff-input[^>]*>([\s\S]*?)<\/textarea>/gi,
    ) || []) {
      const text = input
        .replace(/^<textarea[^>]*>/i, "")
        .replace(/<\/textarea>$/i, "");
      let parsed;
      try {
        parsed = JSON.parse(
          text
            .replace(/&lt;/g, "<")
            .replace(/&gt;/g, ">")
            .replace(/&amp;/g, "&"),
        );
      } catch {}
      if (
        !["before", "after", "patch"].every(
          (key) => typeof parsed?.[key] === "string",
        )
      )
        list.push(
          `${at}: a diff input is not JSON with before, after and patch`,
        );
    }
  }
  // Reading the body's width is fine; writing to the frame's root elements
  // restyles the whole app.
  const mutation =
    /document\.(body|documentElement)\.(style|className|classList|dataset|innerHTML|setAttribute|append|prepend|insertAdjacent|replaceChildren|remove)\b/;
  js.split("\n").forEach((line, index) => {
    const hit = line.match(mutation);
    if (hit) list.push(`plan.js line ${index + 1} restyles document.${hit[1]}`);
  });
  return list;
}

export async function frameBundle() {
  const [shell, style, script, notifications, choices, draft, activity] =
    await Promise.all(
      [
        "frame.html",
        "frame.css",
        "frame.js",
        "notifications.mjs",
        "choices.mjs",
        "draft.mjs",
        "activity.mjs",
      ].map((name) => fs.readFile(new URL(name, assets), "utf8")),
    );
  const roots = componentRoots();
  const [componentCss, componentJs] = await Promise.all([
    componentStyles(roots),
    componentBehaviors(roots),
  ]);
  return {
    shell,
    style,
    script,
    notifications,
    choices,
    draft,
    activity,
    componentCss,
    componentJs,
  };
}

export async function assemble(
  data,
  { css = "", js = "", allowUnknownPages = false, bundle } = {},
) {
  const found = problems(data, js, { allowUnknownPages });
  if (found.length) throw new Error(found.join("\n"));
  const {
    shell,
    style,
    script,
    notifications,
    choices,
    draft,
    activity,
    componentCss,
    componentJs,
  } = bundle || (await frameBundle());
  if (/<\/style/i.test(css) || /<\/script/i.test(js))
    throw new Error(
      "Custom CSS/JS cannot contain HTML closing style/script tags; escape the less-than character in strings.",
    );
  const html = shell
    .replace(
      "<!-- FRAME_STYLE -->",
      // The cascade ranks an unlayered rule above every layered one, so the
      // frame takes a layer of its own rather than staying outside them. A
      // component rule then beats a plan rule of any specificity, and a plan
      // that means it can still say !important.
      // Page CSS arrives scoped to its page. Nesting it inside the component
      // scope would exclude the root itself.
      () =>
        `<style>\n@layer frame, plan, components;\n@layer frame {\n${style}\n}\n` +
        `@layer plan {\n${css}\n}\n@scope (#page-content) {\n@layer components {\n${componentCss}\n}\n}\n` +
        `</style>`,
    )
    .replace(
      "<!-- FRAME_SCRIPT -->",
      () =>
        `<script type="module">\n${notifications}\n${choices}\n${draft}\n${activity}\n${script}\n${componentJs}\n</script>`,
    )
    // A module, and after the frame's, so the plan's own script sees planUI
    // and can register a component of its own before the first page renders.
    .replace(
      "<!-- CUSTOM_SCRIPT -->",
      () => `<script type="module">\n${js}\n</script>`,
    )
    .replace(
      /(<script type="application\/json" id="plan-data">)[\s\S]*?(<\/script>)/,
      (_, start, end) =>
        start + JSON.stringify(data).replaceAll("<", "\\u003c") + end,
    );
  artifactData(html);
  return html;
}

// Revisions reuse page IDs, and the reader keeps several revisions loaded,
// so page CSS and scripts match the revision as well as the page.
export function pageScope(id, revision) {
  return `#page-content[data-page-id="${id}"][data-revision="${revision}"]`;
}

export function pageScripts(pages, revision) {
  return pages
    .filter((page) => page.jsText)
    .map((page) => {
      const encoded = Buffer.from(page.jsText).toString("base64");
      return `import("data:text/javascript;base64,${encoded}").then(({ setup }) => {
        if (typeof setup !== "function") throw new Error("Page ${page.id} must export setup");
        const run = ({ detail }) => {
          if (detail.page.id === ${JSON.stringify(page.id)} && detail.revision === ${JSON.stringify(revision)}) setup(detail.element, window.planUI);
        };
        window.addEventListener("plan:page", run);
        if (window.planUI?.page?.id === ${JSON.stringify(page.id)} && window.planUI?.revision === ${JSON.stringify(revision)})
          setup(document.getElementById("page-content"), window.planUI);
      }).catch((error) => console.error("Page ${page.id} script:", error));`;
    })
    .join("\n");
}

export async function buildPage(source, input) {
  const read = (file) =>
    fs.readFile(path.resolve(path.dirname(source), file), "utf8");
  const { page: rawPage, ...outer } = input;
  if (!rawPage || typeof rawPage !== "object" || Array.isArray(rawPage))
    throw new Error("Page source requires one page object");
  if (rawPage.file && rawPage.html !== undefined)
    throw new Error("Use file or html for a page, not both");
  const page = { ...rawPage };
  if (page.file) page.html = await read(page.file);
  delete page.file;
  if (page.css) page.cssText = await read(page.css);
  if (page.js) page.jsText = await read(page.js);
  delete page.css;
  delete page.js;
  if (page.prototypes)
    page.prototypes = await Promise.all(
      page.prototypes.map(async ({ file, ...prototype }) => {
        if (file && prototype.html !== undefined)
          throw new Error("Use file or html for a prototype, not both");
        return { ...prototype, ...(file ? { html: await read(file) } : {}) };
      }),
    );
  if (page.agreements)
    page.agreements = await Promise.all(
      page.agreements.map(async ({ file, ...entry }) => {
        if (file && entry.html !== undefined)
          throw new Error("Use file or html for an agreement, not both");
        return { ...entry, ...(file ? { html: await read(file) } : {}) };
      }),
    );
  const record = validPage({ ...outer, page });
  const data = pagePlan(record);
  const css = page.cssText
    ? `@scope (${pageScope(page.id, record.revision)}) { ${page.cssText} }`
    : "";
  // assemble checks the script the frame runs, which carries the page's own
  // script encoded, so the page's script is checked here as written.
  const authoredProblems = problems(data, page.jsText || "", {
    allowUnknownPages: true,
  });
  if (authoredProblems.length) throw new Error(authoredProblems.join("\n"));
  const preview = await assemble(data, {
    css,
    js: pageScripts([page], record.revision),
    allowUnknownPages: true,
  });
  return preview.replace(
    "</body>",
    () =>
      `<script type="application/json" id="page-data">${JSON.stringify(record).replaceAll("<", "\\u003c")}</script></body>`,
  );
}

export async function build(source) {
  return buildPage(source, JSON.parse(await fs.readFile(source, "utf8")));
}

/** Whether this file is the one Node was asked to run, symlinks resolved. */
function isMain(argv1 = process.argv[1]) {
  if (!argv1) return false;
  try {
    return (
      realpathSync(path.resolve(argv1)) ===
      realpathSync(fileURLToPath(import.meta.url))
    );
  } catch {
    return false;
  }
}

if (isMain()) {
  try {
    const [source, output, ...extra] = process.argv.slice(2);
    if (!source || !output || extra.length)
      throw new Error("Usage: node scripts/build.mjs SOURCE.json OUTPUT.html");
    const html = await build(path.resolve(source));
    await fs.writeFile(output, html, { flag: "wx", mode: 0o600 });
    console.log(path.resolve(output));
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}
