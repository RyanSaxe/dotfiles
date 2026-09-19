#!/usr/bin/env node
/**
 * document.json and its pages become one HTML file. The lines an excerpt
 * shows are read from the repository at the document's ref, never from the
 * page, so a document cannot misquote the code it explains.
 */
import { realpathSync } from "node:fs";
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { attribute, check, excerpts, fileAt, resolveRef } from "./check.mjs";

const assets = new URL("../assets/", import.meta.url);

const escape = (text) =>
  text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

/** Rows for an excerpt, from the file as it is at the commit. */
export function excerptRows(text, first, last) {
  const all = text.split("\n");
  const rows = [];
  for (let number = first; number <= last; number += 1)
    rows.push(
      `<div class="row" data-line="${number}"><span class="num">${number}</span><span class="src">${escape(all[number - 1] ?? "")}</span></div>`,
    );
  return rows.join("\n");
}

/**
 * Put the repository's lines into every excerpt on a page. The agent wrote
 * the figure, its attributes and its notes; the code between them is ours.
 */
export async function fillExcerpts(html, commit, cwd) {
  let out = "";
  let cursor = 0;
  for (const excerpt of excerpts(html)) {
    const [first, last] = excerpt.lines.split("-").map(Number);
    const text = await fileAt(commit, excerpt.file, cwd);
    const open = excerpt.index + excerpt.tag.length;
    out += html.slice(cursor, open);
    out += `\n<div class="excerpt-code" data-lang="${escape(excerpt.language)}">\n${excerptRows(text, first, last)}\n</div>`;
    cursor = open;
  }
  return out + html.slice(cursor);
}

/**
 * A diagram written as a file arrives in the page as text. Mermaid source is
 * text inside the page, so label markup has to be escaped; written inline,
 * the spans would parse as HTML and drop out of the source.
 */
export async function inlineDiagrams(html, read) {
  let out = "";
  let cursor = 0;
  const tags = html.matchAll(
    /<div\b(?=[^>]*\bdata-diagram\b)(?=[^>]*\bdata-file=)[^>]*>/g,
  );
  for (const match of tags) {
    const file = attribute(match[0], "data-file");
    const open = match.index + match[0].length;
    out += html.slice(cursor, open) + "\n" + escape(await read(file)) + "\n";
    cursor = open;
  }
  return out + html.slice(cursor);
}

export async function assemble(document, { css = "" } = {}) {
  const [shell, style, script] = await Promise.all(
    ["frame.html", "frame.css", "frame.js"].map((name) =>
      fs.readFile(new URL(name, assets), "utf8"),
    ),
  );
  if (/<\/style/i.test(css))
    throw Error("A document stylesheet cannot contain a closing style tag.");
  return shell
    .replace(
      "<title>Visual review</title>",
      () => `<title>${escape(document.title)}</title>`,
    )
    .replace(
      "<!-- FRAME_STYLE -->",
      () => `<style>\n${style}\n${css}\n</style>`,
    )
    .replace(
      "<!-- FRAME_SCRIPT -->",
      () => `<script type="module">\n${script}\n</script>`,
    )
    .replace(
      /(<script type="application\/json" id="document-data">)[\s\S]*?(<\/script>)/,
      (_, start, end) =>
        start + JSON.stringify(document).replaceAll("<", "\\u003c") + end,
    );
}

/** Read a description and everything it points at. */
export async function load(source) {
  const raw = JSON.parse(await fs.readFile(source, "utf8"));
  const directory = path.dirname(source);
  const read = async (file) => {
    try {
      return await fs.readFile(path.resolve(directory, file), "utf8");
    } catch (error) {
      if (error.code === "ENOENT")
        throw Error(`${file} is not beside the description`);
      throw error;
    }
  };
  const cwd = raw.repository
    ? path.resolve(directory, raw.repository)
    : process.cwd();
  const css = raw.css ? await read(raw.css) : "";
  const document = { ...raw };
  delete document.css;
  delete document.repository;
  if (raw.opens) document.opens = await read(raw.opens);
  document.pages = await Promise.all(
    (raw.pages || []).map(async ({ file, ...page }) => {
      if (file && page.html !== undefined)
        throw Error(`Page ${page.id}: use file or html, not both`);
      const html = file ? await read(file) : page.html;
      return { ...page, html: await inlineDiagrams(html, read) };
    }),
  );
  return { document, css, cwd };
}

const notBuilt = (problems) =>
  Error(["The document was not built:", ...problems].join("\n  "));

export async function build(source) {
  let loaded;
  try {
    loaded = await load(source);
    loaded.document.ref = loaded.document.ref || "HEAD";
    loaded.document.commit = await resolveRef(loaded.document.ref, loaded.cwd);
  } catch (error) {
    throw notBuilt([error.message]);
  }
  const { document, css, cwd } = loaded;
  const frameCss = await fs.readFile(new URL("frame.css", assets), "utf8");
  const problems = await check(document, { css, frameCss, cwd });
  if (problems.length) throw notBuilt(problems);
  for (const page of document.pages)
    page.html = await fillExcerpts(page.html, document.commit, cwd);
  document.builtAt = new Date().toISOString();
  return assemble(document, { css });
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

/** The output path is free, or holds a document this builder wrote. */
async function writable(output) {
  try {
    const existing = await fs.readFile(output, "utf8");
    return existing.includes('id="document-data"');
  } catch (error) {
    if (error.code === "ENOENT") return true;
    throw error;
  }
}

if (isMain()) {
  try {
    const [source, output, ...extra] = process.argv.slice(2);
    if (!source || !output || extra.length)
      throw Error("Usage: node scripts/build.mjs document.json OUTPUT.html");
    const html = await build(path.resolve(source));
    if (!(await writable(output)))
      throw Error(
        `${output} exists and is not a document this builder wrote; choose another path`,
      );
    await fs.mkdir(path.dirname(path.resolve(output)), { recursive: true });
    await fs.writeFile(output, html, { mode: 0o600 });
    console.log(path.resolve(output));
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}
