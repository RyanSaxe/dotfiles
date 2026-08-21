// Exercises the pure review-to-dashboard mapping and the shared dashboard
// renderer without opening a terminal or contacting GitHub.

import assert from "node:assert/strict";

import { rankDashboardItems, renderDashboard } from "../src/dashboard.js";
import { reviewItem } from "../src/review-dashboard.js";
import type { AttentionItem } from "../src/attention/types.js";
import type { Palette } from "../src/theme.js";

const item: AttentionItem = {
  id: "review:fixture",
  kind: "review_comment",
  repository: "example/repo",
  number: 7,
  title: "Improve the review seam",
  context: {
    body: "Keep the dashboard context useful and concise.",
    author: { login: "ryansaxe", kind: "user" },
    ciState: "SUCCESS",
  },
  url: "https://github.com/example/repo/pull/7",
  summary: "Please take another look",
  actor: { login: "reviewer", kind: "user" },
  createdAt: "2026-08-19T16:00:00Z",
  priority: "normal",
};

const palette: Palette = {
  mode: "dark",
  accent: "#f9e2af",
  notify: "#f38ba8",
  base: "#1e1e2e",
  crust: "#11111b",
  surface0: "#313244",
  text: "#cdd6f4",
  dim: "#7f849c",
  dim2: "#6c7086",
  lavender: "#b4befe",
  yellow: "#f9e2af",
  mauve: "#cba6f7",
  peach: "#fab387",
  green: "#a6e3a1",
  red: "#f38ba8",
  statusWorking: "#cba6f7",
  statusWaiting: "#fab387",
  statusDone: "#a6e3a1",
};

const dashboardItem = reviewItem(item, false);
assert.equal(dashboardItem.project, "repo");
assert.equal(dashboardItem.reference, "#7");
assert.equal(dashboardItem.kind, "Review");
assert.equal(dashboardItem.state, "needs you");
assert.equal(dashboardItem.tone, "waiting");
assert.deepEqual(dashboardItem.details, [
  "PR author  @ryansaxe",
  "CI         success",
  "",
  "Keep the dashboard context useful and concise.",
]);
assert.equal(rankDashboardItems([dashboardItem], "rvs").length, 1);
assert.equal(rankDashboardItems([dashboardItem], "does-not-match").length, 0);

const rendered = renderDashboard(
  {
    surface: "reviews",
    items: [dashboardItem],
    status: "1 open · 0 seen",
    emptyMessage: "Review inbox is clear",
    error: null,
  },
  0,
  palette,
  100,
  24,
);
const plain = rendered.replace(/\x1b\[[0-9;?]*[ -/]*[@-~]/g, "");
assert.match(plain, /Reviews  \|  Tasks/);
assert.match(plain, /repo/);
assert.match(plain, /Improve the review seam/);
assert.match(plain, /Keep the dashboard context useful and concise/);
assert.match(plain, /Enter Open/);

const searching = renderDashboard(
  {
    surface: "reviews",
    items: [dashboardItem],
    status: "1 open · 0 seen",
    emptyMessage: "Review inbox is clear",
    error: null,
  },
  0,
  palette,
  100,
  24,
  "rvs",
  true,
).replace(/\x1b\[[0-9;?]*[ -/]*[@-~]/g, "");
assert.match(searching, /\/rvs · 1\/1 matches/);
assert.match(searching, /Enter Apply/);
console.log("review dashboard checks passed");
