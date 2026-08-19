// Exercises the Review dashboard's selection protocol without launching fzf.
// The interactive surface is intentionally a thin wrapper around these pure
// row and key-decoding functions.

import assert from "node:assert/strict";

import { formatReviewRow, parseFzfOutput } from "../src/review-dashboard.js";
import type { AttentionItem } from "../src/attention/types.js";

const item: AttentionItem = {
  id: "review:fixture",
  kind: "review_comment",
  repository: "example/repo",
  number: 7,
  title: "Improve the review seam",
  url: "https://github.com/example/repo/pull/7",
  summary: "Please take another look",
  actor: { login: "reviewer", kind: "user" },
  createdAt: "2026-08-19T16:00:00Z",
  priority: "normal",
};

assert.match(formatReviewRow(0, item, false), /repo#7/);
assert.match(formatReviewRow(0, item, true), /✓/);
assert.deepEqual(parseFzfOutput(`\n${formatReviewRow(0, item, false)}\n`), {
  action: "open",
  itemIndex: 0,
});
assert.deepEqual(
  parseFzfOutput(`ctrl-d\n${formatReviewRow(0, item, false)}\n`),
  { action: "ack", itemIndex: 0 },
);
assert.deepEqual(
  parseFzfOutput(`ctrl-r\n${formatReviewRow(0, item, false)}\n`),
  { action: "refresh", itemIndex: 0 },
);
assert.equal(parseFzfOutput(""), null);
console.log("review dashboard checks passed");
