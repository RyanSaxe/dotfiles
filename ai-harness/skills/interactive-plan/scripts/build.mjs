#!/usr/bin/env node
import { realpathSync } from "node:fs";
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { artifactData } from "./session.mjs";

const assets = new URL("../assets/", import.meta.url);

const attribute = (tag, name) => {
  const match = tag.match(new RegExp(`\\s${name}=(?:"([^"]*)"|'([^']*)')`));
  return match ? (match[1] ?? match[2]) : undefined;
};
const controlKinds = ["data-choice", "data-multiselect", "data-question"];

const labelLimit = 24;

/** Structural problems in the assembled pages and the plan's script. */
export function problems(data, js = "") {
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
      if (link?.startsWith("#") && !targets.has(link.slice(1)))
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

export async function assemble(data, { css = "", js = "" } = {}) {
  const found = problems(data, js);
  if (found.length) throw new Error(found.join("\n"));
  const [shell, style, script, notifications, choices, draft] =
    await Promise.all(
      [
        "frame.html",
        "frame.css",
        "frame.js",
        "notifications.mjs",
        "choices.mjs",
        "draft.mjs",
      ].map((name) => fs.readFile(new URL(name, assets), "utf8")),
    );
  if (/<\/style/i.test(css) || /<\/script/i.test(js))
    throw new Error(
      "Custom CSS/JS cannot contain HTML closing style/script tags; escape the less-than character in strings.",
    );
  const html = shell
    .replace(
      "<!-- FRAME_STYLE -->",
      // Plan CSS is scoped to the page's content, so a rule for body, :root,
      // or h1 cannot restyle the frame.
      () => `<style>\n${style}\n@scope (#page-content) {\n${css}\n}\n</style>`,
    )
    .replace("<!-- CUSTOM_SCRIPT -->", () => `<script>\n${js}\n</script>`)
    .replace(
      "<!-- FRAME_SCRIPT -->",
      () =>
        `<script type="module">\n${notifications}\n${choices}\n${draft}\n${script}\n</script>`,
    )
    .replace(
      /(<script type="application\/json" id="plan-data">)[\s\S]*?(<\/script>)/,
      (_, start, end) =>
        start + JSON.stringify(data).replaceAll("<", "\\u003c") + end,
    );
  artifactData(html);
  return html;
}

export async function build(source) {
  const data = JSON.parse(await fs.readFile(source, "utf8"));
  const read = (file) =>
    fs.readFile(path.resolve(path.dirname(source), file), "utf8");
  const css = data.css ? await read(data.css) : "";
  const js = data.js ? await read(data.js) : "";
  delete data.css;
  delete data.js;
  data.pages = await Promise.all(
    data.pages.map(async ({ file, ...page }) => {
      if (file && page.html !== undefined)
        throw new Error("Use file or html for a page, not both");
      return file ? { ...page, html: await read(file) } : page;
    }),
  );
  if (data.prototypes) {
    data.prototypes = await Promise.all(
      data.prototypes.map(async ({ file, ...prototype }) => {
        if (file && prototype.html !== undefined)
          throw new Error("Use file or html for a prototype, not both");
        return file ? { ...prototype, html: await read(file) } : prototype;
      }),
    );
  }
  if (Array.isArray(data.agreements))
    data.agreements = await Promise.all(
      data.agreements.map(async ({ file, ...entry }) => {
        if (file && entry.html !== undefined)
          throw new Error("Use file or html for an agreement, not both");
        return file ? { ...entry, html: await read(file) } : entry;
      }),
    );
  return assemble(data, { css, js });
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
