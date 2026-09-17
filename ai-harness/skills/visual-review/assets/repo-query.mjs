/**
 * Questions answered from a repository's path index.
 *
 * The helper answers these from git, and an exported page answers them from
 * the index the session embedded. Sharing the functions is what keeps an
 * export behaving like the session it came from.
 */

export const PATH_LIMIT = 200;
export const PATH_DEFAULT = 50;

export function searchPaths(all, query, limit) {
  const size = Math.min(Math.max(Number(limit) || PATH_DEFAULT, 1), PATH_LIMIT);
  const needle = String(query ?? "").toLowerCase();
  if (!needle) return { total: all.length, matches: all.slice(0, size) };
  const matches = [];
  let total = 0;
  for (const candidate of all) {
    if (!candidate.toLowerCase().includes(needle)) continue;
    total += 1;
    if (matches.length < size) matches.push(candidate);
  }
  return { total, matches };
}

/** A path is a file when the index holds it, a directory when it prefixes one. */
export function describeEntry(all, target) {
  if (!target) return { exists: true, type: "directory" };
  if (all.includes(target)) return { exists: true, type: "file" };
  const prefix = target + "/";
  const directory = all.some((candidate) => candidate.startsWith(prefix));
  return { exists: directory, type: directory ? "directory" : null };
}

/** One directory's entries, taken from the index rather than from git. */
export function treeFromIndex(all, directory) {
  const prefix = directory ? directory + "/" : "";
  const names = new Map();
  for (const candidate of all) {
    if (!candidate.startsWith(prefix)) continue;
    const rest = candidate.slice(prefix.length);
    const cut = rest.indexOf("/");
    if (cut === -1) names.set(rest, "file");
    else names.set(rest.slice(0, cut), "directory");
  }
  const order = (a, b) => (a < b ? -1 : a > b ? 1 : 0);
  return [...names]
    .map(([name, type]) => ({ name, type }))
    .sort(
      (a, b) =>
        (a.type === "directory" ? 0 : 1) - (b.type === "directory" ? 0 : 1) ||
        order(a.name.toLowerCase(), b.name.toLowerCase()) ||
        order(a.name, b.name),
    );
}
