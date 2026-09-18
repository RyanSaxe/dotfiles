import assert from "node:assert/strict";
import test from "node:test";
import {
  fuzzyPaths,
  searchPaths,
} from "../../ai-harness/skills/visual-review/assets/repo-query.mjs";

const paths = [
  "README.md",
  "ai-harness/skills/interactive-plan/scripts/session.mjs",
  "ai-harness/skills/visual-review/scripts/session.mjs",
  "ai-harness/skills/visual-review/assets/app.js",
  "tests/visual-review/fixtures/pages/excerpt.md",
  "src/client.py",
  "src/sessions/archive/long-forgotten-session-notes.md",
];

test("ranks a file-name match ahead of a longer path with the same letters", () => {
  const found = fuzzyPaths(paths, "sessmjs");
  assert.deepEqual(
    found.map((match) => match.path),
    [
      "ai-harness/skills/visual-review/scripts/session.mjs",
      "ai-harness/skills/interactive-plan/scripts/session.mjs",
    ],
    "both session.mjs files, the shorter path first",
  );
  assert.equal(
    fuzzyPaths(paths, "sess")[0].path,
    "ai-harness/skills/visual-review/scripts/session.mjs",
    "a file name that holds the whole query outranks a directory that does",
  );
});

test("marks the characters that matched, in path order", () => {
  const [best] = fuzzyPaths(paths, "cli");
  assert.equal(best.path, "src/client.py");
  assert.deepEqual(best.positions, [4, 5, 6]);
  const [readme] = fuzzyPaths(paths, "readme");
  assert.deepEqual(
    readme.positions,
    [0, 1, 2, 3, 4, 5],
    "case does not matter",
  );
});

test("prefers a run in the file name, then segment starts, then scattered letters", () => {
  const all = ["zzazzbzzc.md", "a/b/c.md", "docs/abc.md"];
  assert.deepEqual(
    fuzzyPaths(all, "abc").map((match) => match.path),
    ["docs/abc.md", "a/b/c.md", "zzazzbzzc.md"],
  );
});

test("returns nothing for an empty query and honors the limit", () => {
  assert.deepEqual(fuzzyPaths(paths, ""), []);
  assert.deepEqual(fuzzyPaths(paths, "   "), []);
  assert.equal(fuzzyPaths(paths, "s", 2).length, 2);
  assert.deepEqual(fuzzyPaths(paths, "qqq"), [], "no path has those letters");
});

test("the route answer counts matches and tracked files separately", () => {
  const answer = searchPaths(paths, "session", 1);
  assert.equal(answer.matches.length, 1);
  assert.equal(answer.total, 3);
  assert.equal(answer.tracked, paths.length);
  assert.deepEqual(searchPaths(paths, "", 5), {
    total: 0,
    tracked: paths.length,
    matches: [],
  });
});
