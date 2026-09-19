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
// A colour literal in a document stylesheet survives one theme and vanishes
// in the other; only tokens are allowed.
const colourLiteral =
  /#[0-9a-f]{3,8}\b|\b(?:rgb|rgba|hsl|hsla|oklch|oklab|color)\(/i;

export const attribute = (tag, name) =>
  tag.match(new RegExp(`\\b${name}=(?:"([^"]*)"|'([^']*)')`))?.[1] ??
  tag.match(new RegExp(`\\b${name}=(?:"([^"]*)"|'([^']*)')`))?.[2];

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

  return problems;
}
