#!/usr/bin/env node
import { realpathSync } from "node:fs";
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { artifactData } from "./session.mjs";

const assets = new URL("../assets/", import.meta.url);

export async function assemble(data, { css = "", js = "" } = {}) {
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
      () => `<style>\n${style}\n${css}\n</style>`,
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
