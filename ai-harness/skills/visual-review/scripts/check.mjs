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

  return problems;
}
