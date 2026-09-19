/**
 * The refusals. Every check reads the description, the pages and the
 * repository; none needs a browser. build.mjs runs these before it writes
 * anything, and a document with a single problem is not written.
 */
import { execFile } from "node:child_process";
import { promisify } from "node:util";

const run = promisify(execFile);
// The repository is the one at cwd, whatever GIT_DIR a hook or a rebase
// exported to the process that runs the build.
const env = { ...process.env };
for (const key of ["GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE"])
  delete env[key];

export const idPattern = /^[A-Za-z0-9_-]+$/;
const linesPattern = /^(\d+)-(\d+)$/;
// A colour literal in a document stylesheet survives one theme and vanishes
// in the other; only tokens are allowed.
const colourLiteral =
  /#[0-9a-f]{3,8}\b|\b(?:rgb|rgba|hsl|hsla|oklch|oklab|color)\(/i;

export const attribute = (tag, name) =>
  tag.match(new RegExp(`\\b${name}=(?:"([^"]*)"|'([^']*)')`))?.[1] ??
  tag.match(new RegExp(`\\b${name}=(?:"([^"]*)"|'([^']*)')`))?.[2];

const figureTag = (kind) =>
  new RegExp(
    `<figure\\b[^>]*\\bclass=(?:"[^"]*\\b${kind}\\b[^"]*"|'[^']*\\b${kind}\\b[^']*')[^>]*>`,
    "g",
  );

/** Each excerpt figure's opening tag, what it asks for, and its body. */
export function excerpts(html) {
  const found = [];
  for (const match of html.matchAll(figureTag("excerpt"))) {
    const tag = match[0];
    const file = attribute(tag, "data-file");
    const lines = attribute(tag, "data-lines");
    const language = attribute(tag, "data-language");
    const open = match.index + tag.length;
    const close = html.indexOf("</figure>", open);
    const body = html.slice(open, close < 0 ? undefined : close);
    found.push({ tag, index: match.index, file, lines, language, body });
  }
  return found;
}

const unescape = (text) =>
  text
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&amp;/g, "&");

/** Whether a change figure's textarea holds what the viewer reads. */
function changeInput(body) {
  const input = body.match(
    /<textarea\b[^>]*\bdata-diff-input\b[^>]*>([\s\S]*?)<\/textarea>/,
  );
  if (!input) return null;
  try {
    const parsed = JSON.parse(unescape(input[1]));
    return ["before", "after", "patch"].every(
      (key) => typeof parsed[key] === "string",
    )
      ? parsed
      : null;
  } catch {
    return null;
  }
}

/** Node ids and label classes in a Mermaid source. */
export function diagramFacts(source) {
  const nodes = new Set();
  const classes = new Set();
  const marks = [];
  const keywords =
    /^(flowchart|graph|subgraph|end|class|classDef|style|direction|click|linkStyle)$/;
  for (const raw of source.split("\n")) {
    const line = raw.trim();
    if (!line || line.startsWith("%%")) continue;
    for (const found of line.matchAll(/class=['"]([^'"]+)['"]/g))
      for (const name of found[1].split(/\s+/)) if (name) classes.add(name);
    const mark = line.match(
      /^class\s+([A-Za-z0-9_,\s]+)\s+([A-Za-z0-9_-]+)\s*$/,
    );
    if (mark) {
      marks.push({
        ids: mark[1]
          .split(",")
          .map((id) => id.trim())
          .filter(Boolean),
        name: mark[2],
      });
      continue;
    }
    // Edge labels sit between the arrow's halves or in pipes and are not
    // nodes; drop them before reading ids off the arrows.
    const bare = line
      .replace(/\|[^|]*\|/g, " ")
      .replace(/--\s+[^-]*?\s+-->/g, " --> ")
      .replace(/-\.\s+[^-]*?\s+\.->/g, " --> ")
      .replace(/==\s+[^=]*?\s+==>/g, " --> ");
    const declared = bare.match(
      /^(?:subgraph\s+)?([A-Za-z0-9_]+)\s*(?:[[({]|$)/,
    );
    if (declared && !keywords.test(declared[1])) nodes.add(declared[1]);
    for (const edge of bare.matchAll(
      /([A-Za-z0-9_]+)(?:[[({][^\]})]*[\]})])?\s*(?:-->|---|-\.->|==>)/g,
    ))
      nodes.add(edge[1]);
    for (const edge of bare.matchAll(
      /(?:-->|---|-\.->|==>)\s*([A-Za-z0-9_]+)/g,
    ))
      nodes.add(edge[1]);
  }
  return { nodes, classes, marks };
}

/** The class names a stylesheet styles, by selector. */
export function styledClasses(css) {
  const names = new Set();
  for (const found of css.matchAll(/\.([A-Za-z_][\w-]*)/g)) names.add(found[1]);
  return names;
}

export async function resolveRef(ref, cwd) {
  try {
    const { stdout } = await run(
      "git",
      ["rev-parse", "--verify", `${ref}^{commit}`],
      { cwd, env },
    );
    return stdout.trim();
  } catch (error) {
    if (error.code === "ENOENT")
      throw Error("Git is required to build a document.");
    if (/not a git repository/.test(error.stderr || ""))
      throw Error(
        `${cwd} is not inside a repository; build from the repository or set repository in the description`,
      );
    throw Error(`ref ${ref} is not a commit in this repository`);
  }
}

export async function fileAt(commit, file, cwd) {
  try {
    const { stdout } = await run("git", ["show", `${commit}:${file}`], {
      cwd,
      env,
      encoding: "utf8",
      maxBuffer: 64 * 1024 * 1024,
    });
    return stdout;
  } catch (error) {
    throw Error(`${file} does not exist at ${commit.slice(0, 7)}`);
  }
}

/**
 * Check a loaded description. `document` is the parsed JSON with page HTML
 * already read in; `css` is the document's own stylesheet or an empty
 * string; `frameCss` is the shipped one. Returns the problems found, each
 * a sentence naming what and where.
 */
export async function check(document, { css = "", frameCss, cwd }) {
  const problems = [];
  const say = (text) => problems.push(text);

  if (!idPattern.test(document.documentId || ""))
    say("documentId must be letters, digits, underscores or hyphens");
  if (typeof document.title !== "string" || !document.title.trim())
    say("title is required");
  if (!Array.isArray(document.pages) || document.pages.length === 0) {
    say("at least one page is required");
    return problems;
  }
  const pageIds = new Set();
  for (const page of document.pages) {
    if (!idPattern.test(page.id || ""))
      say(`page id ${JSON.stringify(page.id)} is not valid`);
    else if (pageIds.has(page.id)) say(`page id ${page.id} is used twice`);
    pageIds.add(page.id);
    if (typeof page.title !== "string" || !page.title.trim())
      say(`page ${page.id} needs a title`);
    if (typeof page.html !== "string") say(`page ${page.id} has no html`);
    if (page.depth !== undefined && ![0, 1].includes(page.depth))
      say(`page ${page.id} depth must be 0 or 1`);
  }

  const commit = document.commit;
  const styled = new Set([...styledClasses(frameCss), ...styledClasses(css)]);

  const sources = [];
  if (document.opens)
    sources.push({ where: "the opening diagram", source: document.opens });
  for (const page of document.pages)
    for (const found of (page.html || "").matchAll(
      /<div\b[^>]*\bdata-diagram\b[^>]*>([\s\S]*?)<\/div>/g,
    )) {
      // Inline, a diagram is text: a raw span here has already been parsed
      // out of the source by the time Mermaid sees it.
      if (/<span\b/.test(found[1]))
        say(
          `page ${page.id}: a diagram label holds raw markup; write it as text (&lt;span …&gt;) or put the diagram in a file named by data-file`,
        );
      sources.push({ where: `page ${page.id}`, source: found[1] });
    }
  for (const { where, source } of sources) {
    const facts = diagramFacts(source);
    for (const name of facts.classes)
      if (!styled.has(name))
        say(`${where}: label class "${name}" is styled by nothing`);
    for (const mark of facts.marks) {
      if (!styled.has(mark.name))
        say(`${where}: node class "${mark.name}" is styled by nothing`);
      for (const id of mark.ids)
        if (!facts.nodes.has(id))
          say(`${where}: "${id}" is marked but is not a node`);
    }
  }

  if (css && colourLiteral.test(css))
    say("the document stylesheet sets a colour that is not a token");

  for (const page of document.pages) {
    for (const excerpt of excerpts(page.html || "")) {
      const spot = `page ${page.id}, excerpt ${excerpt.file || "(no file)"}`;
      if (!excerpt.file) {
        say(`${spot}: data-file is required`);
        continue;
      }
      if (!excerpt.language) say(`${spot}: data-language is required`);
      const range = (excerpt.lines || "").match(linesPattern);
      if (!range) {
        say(`${spot}: data-lines must be first-last`);
        continue;
      }
      const [first, last] = [Number(range[1]), Number(range[2])];
      if (first < 1 || last < first) {
        say(`${spot}: data-lines ${excerpt.lines} is not a range`);
        continue;
      }
      for (const note of excerpt.body.matchAll(/<li\b[^>]*>/g)) {
        const line = Number(attribute(note[0], "data-line"));
        const span = attribute(note[0], "data-span")?.match(linesPattern);
        if (line && (line < first || line > last))
          say(
            `${spot}: a note on line ${line} is outside lines ${excerpt.lines}`,
          );
        if (span && (Number(span[1]) < first || Number(span[2]) > last))
          say(
            `${spot}: a note's span ${span[0]} is outside lines ${excerpt.lines}`,
          );
      }
      if (!commit) continue;
      let text;
      try {
        text = await fileAt(commit, excerpt.file, cwd);
      } catch (error) {
        say(`${spot}: ${error.message}`);
        continue;
      }
      const count = text.split("\n").length - (text.endsWith("\n") ? 1 : 0);
      if (last > count)
        say(
          `${spot}: lines ${excerpt.lines} run past the end of the file (${count} lines)`,
        );
    }
    for (const match of (page.html || "").matchAll(figureTag("change"))) {
      const spot = `page ${page.id}, change ${attribute(match[0], "data-file") || "(no file)"}`;
      const open = match.index + match[0].length;
      const close = page.html.indexOf("</figure>", open);
      const body = page.html.slice(open, close < 0 ? undefined : close);
      if (!changeInput(body))
        say(
          `${spot}: the input is not JSON with before, after and patch; components/diff/diff.mjs writes it, named by data-change`,
        );
    }
  }
  return problems;
}
