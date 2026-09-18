/**
 * Questions answered from a list of paths.
 *
 * The helper answers them over the tracked files at a ref, and an exported
 * page over the files the session served. Sharing the functions is what keeps
 * an export ranking like the session it came from.
 */

export const PATH_LIMIT = 200;
export const PATH_DEFAULT = 50;

/**
 * Where `needle` matches `haystack` in order from `from`, or null.
 *
 * Greedy left to right, which is what a reader typing a path expects: each
 * character lands on its first chance after the one before.
 */
function matchInOrder(haystack, needle, from = 0) {
  const positions = [];
  let at = from;
  for (const character of needle) {
    at = haystack.indexOf(character, at);
    if (at === -1) return null;
    positions.push(at);
    at += 1;
  }
  return positions;
}

function scoreMatch(path, positions) {
  let score = 0;
  for (const [index, at] of positions.entries()) {
    if (at === 0 || path[at - 1] === "/") score += 3;
    else if (index && at === positions[index - 1] + 1) score += 2;
    else score += 1;
    if (index) score -= at - positions[index - 1] - 1;
  }
  return score;
}

/**
 * The paths whose characters contain `query` in order, best first.
 *
 * A match at the start of a path segment scores 3, one adjacent to the
 * previous match 2, any other 1, less one per character skipped between
 * matches, plus 5 when the whole query fits inside the file name. Ties go to
 * the shorter path. Returns [{ path, score, positions }].
 */
export function fuzzyPaths(all, query, limit = PATH_DEFAULT) {
  const needle = String(query ?? "").toLowerCase();
  if (!needle) return [];
  const found = [];
  for (const path of all) {
    const lower = path.toLowerCase();
    const cut = lower.lastIndexOf("/") + 1;
    let positions = matchInOrder(lower, needle, cut);
    let score;
    if (positions) score = scoreMatch(lower, positions) + 5;
    else {
      positions = matchInOrder(lower, needle);
      if (!positions) continue;
      score = scoreMatch(lower, positions);
    }
    found.push({ path, score, positions });
  }
  found.sort(
    (a, b) =>
      b.score - a.score ||
      a.path.length - b.path.length ||
      (a.path < b.path ? -1 : a.path > b.path ? 1 : 0),
  );
  return found.slice(0, limit);
}

/** The /repo/paths answer: the best matches, how many matched, how many exist. */
export function searchPaths(all, query, limit) {
  const size = Math.min(Math.max(Number(limit) || PATH_DEFAULT, 1), PATH_LIMIT);
  const matches = fuzzyPaths(all, query, Infinity);
  return {
    total: matches.length,
    tracked: all.length,
    matches: matches.slice(0, size),
  };
}

/** A path is a file when the index holds it, a directory when it prefixes one. */
export function describeEntry(all, target) {
  if (!target) return { exists: true, type: "directory" };
  if (all.includes(target)) return { exists: true, type: "file" };
  const prefix = target + "/";
  const directory = all.some((candidate) => candidate.startsWith(prefix));
  return { exists: directory, type: directory ? "directory" : null };
}
