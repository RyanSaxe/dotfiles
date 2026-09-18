/**
 * Where the page gets its answers.
 *
 * Live, that is the helper. Exported, it is the data the session embedded in
 * the file. Everything above this module asks the same questions either way,
 * which is what lets one app.js serve both.
 */
import { describeEntry, searchPaths } from "./repo-query.mjs";

let offline = null;

export const isOffline = () => offline !== null;

export function useEmbeddedData(data) {
  offline = data;
}

const json = (value) =>
  new Response(JSON.stringify(value), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
const missing = (message) =>
  new Response(JSON.stringify({ error: message }), {
    status: 404,
    headers: { "Content-Type": "application/json" },
  });

/** Answer one request from the embedded session. */
function answer(url) {
  const at = new URL(url, "http://export.invalid");
  const query = at.searchParams;
  const shaFor = (ref) => offline.refs[ref ?? offline.repo.ref];

  if (at.pathname === "/api/state") return json(offline.state);

  if (at.pathname === "/api/page") {
    const markdown =
      offline.pages[`${query.get("question")}/${query.get("id")}`];
    if (markdown === undefined)
      return missing("That page is not in this export");
    return new Response(markdown, {
      status: 200,
      headers: { "Content-Type": "text/markdown; charset=utf-8" },
    });
  }

  const sha = shaFor(query.get("ref"));
  if (!sha && at.pathname.startsWith("/repo/"))
    return missing(`This export does not include the ref ${query.get("ref")}`);
  // The export knows the files the session served and nothing else, so the
  // palette and the reference chips reach only what the file can show.
  const prefix = `file:${sha}:`;
  const served = Object.keys(offline.cache)
    .filter((key) => key.startsWith(prefix))
    .map((key) => key.slice(prefix.length))
    .sort();

  if (at.pathname === "/repo/file") {
    const path = query.get("path");
    const file = offline.cache[`file:${sha}:${path}`];
    if (!file) return missing(`${path} was not opened during this session`);
    return json({ path, ref: query.get("ref") ?? offline.repo.ref, ...file });
  }

  if (at.pathname === "/repo/tree") {
    const path = query.get("path") ?? "";
    const entries = offline.cache[`tree:${sha}:${path}`];
    if (!entries)
      return missing("That directory was not listed during this session");
    return json({ path, ref: query.get("ref") ?? offline.repo.ref, entries });
  }

  if (at.pathname === "/repo/paths")
    return json({
      ref: query.get("ref") ?? offline.repo.ref,
      ...searchPaths(served, query.get("q"), query.get("limit")),
    });

  if (at.pathname === "/repo/exists") {
    const path = query.get("path") ?? "";
    return json({
      path,
      ref: query.get("ref") ?? offline.repo.ref,
      ...describeEntry(served, path),
    });
  }

  if (at.pathname === "/repo/diff") {
    const base = shaFor(query.get("base"));
    const head = shaFor(query.get("head"));
    const path = query.get("path") ?? "";
    const patch = offline.cache[`diff:${base}..${head}:${path}`];
    if (patch === undefined)
      return missing("That diff was not opened during this session");
    return json({
      base: query.get("base"),
      head: query.get("head"),
      path,
      patch,
    });
  }

  return missing("Not in this export");
}

/** The one way anything in the page asks for data. */
export async function request(url, options) {
  if (!offline) return fetch(url, options);
  if (options?.method === "POST")
    throw new Error("This is an exported session; it cannot ask questions.");
  return answer(url);
}
