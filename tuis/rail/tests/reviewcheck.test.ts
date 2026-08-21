// Exercises the pure review-to-dashboard mapping and the shared dashboard
// renderer without opening a terminal or contacting GitHub.

import assert from "node:assert/strict";
import { test } from "node:test";

import { rankDashboardItems, renderDashboard } from "../src/dashboard.js";
import type { DashboardData, DashboardItem } from "../src/dashboard.js";
import { reviewItem } from "../src/review-dashboard.js";
import type { AttentionItem } from "../src/attention/types.js";
import type { Palette } from "../src/theme.js";

const VIEWER = "ryansaxe";

const attention = (over: Partial<AttentionItem> = {}): AttentionItem => ({
  id: "review:fixture",
  kind: "review_comment",
  targetKind: "pull_request",
  repository: "example/repo",
  number: 7,
  title: "Improve the review seam",
  context: {
    body: "## Summary\n\nKeep the dashboard context useful and concise.",
    author: { login: VIEWER, kind: "user" },
    ciState: "SUCCESS",
    failingChecks: [],
  },
  url: "https://github.com/example/repo/pull/7",
  summary: "Please take another look",
  actor: { login: "reviewer", kind: "user" },
  createdAt: "2026-08-19T16:00:00Z",
  priority: "normal",
  ...over,
});

const palette: Palette = {
  mode: "dark",
  accent: "#d8b44a",
  notify: "#69ceea",
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

const strip = (text: string): string =>
  text.replace(/\x1b\[[0-9;?]*[ -/]*[@-~]/g, "");

const frame = (
  items: DashboardItem[],
  extra: Partial<DashboardData> = {},
  ...rest: [number?, string?, boolean?, number?]
): string => {
  const [selected = 0, query = "", searching = false, offset = 0] = rest;
  return strip(
    renderDashboard(
      {
        surface: "reviews",
        items,
        status: `${items.length} need you`,
        emptyMessage: "Review inbox is clear",
        error: null,
        ...extra,
      },
      selected,
      palette,
      100,
      24,
      query,
      searching,
      offset,
    ),
  );
};

test("From is empty where GitHub sends no actor; Author always names someone", () => {
  const commented = reviewItem(attention(), VIEWER);
  assert.equal(commented.from, "@reviewer");
  assert.equal(commented.author, "@ryansaxe");
  assert.equal(commented.authorIsViewer, true);

  const ci = reviewItem(attention({ kind: "ci", actor: null }), VIEWER);
  assert.equal(ci.from, "—");
  assert.equal(ci.author, "@ryansaxe");
});

test("tone follows the object, not the severity", () => {
  assert.equal(reviewItem(attention({ kind: "ci" }), VIEWER).tone, "ci");
  assert.equal(
    reviewItem(attention({ kind: "conversation" }), VIEWER).tone,
    "pull_request",
  );
});

test("the reason phrase never repeats the actor", () => {
  const item = reviewItem(attention({ kind: "conversation" }), VIEWER);
  assert.equal(item.reason, "Commented on your PR");
  assert.ok(!item.reason.includes("reviewer"));
});

test("markdown is stripped from preview bodies", () => {
  const item = reviewItem(attention({ kind: "ci", actor: null }), VIEWER);
  assert.ok(!item.preview.body.join(" ").includes("#"));
  assert.match(item.preview.body.join(" "), /Keep the dashboard context/);
});

test("rows group under their repository", () => {
  const rendered = frame([
    reviewItem(attention({ id: "a" }), VIEWER),
    reviewItem(
      attention({ id: "b", repository: "other/thing", number: 2 }),
      VIEWER,
    ),
  ]);
  assert.match(rendered, /example\/repo/);
  assert.match(rendered, /other\/thing/);
});

test("every rendered line is exactly the frame width", () => {
  // The panel border is placed by reserving inner width. Get that wrong and
  // each preview row ends in a stray │, which is what shipped before.
  for (const line of frame([reviewItem(attention(), VIEWER)]).split("\n")) {
    assert.equal(line.length, 100);
  }
});

test("a long body cannot push the footer off the frame", () => {
  const long = attention({
    summary: "wall of text. ".repeat(400),
  });
  const rendered = frame([reviewItem(long, VIEWER)]);
  assert.equal(rendered.split("\n").length, 24);
  assert.match(rendered, /q Quit/);
  assert.match(rendered, /more lines/);
});

test("scrolling past the end clamps instead of blanking the panel", () => {
  const long = attention({ summary: "paragraph. ".repeat(400) });
  const rendered = frame([reviewItem(long, VIEWER)], {}, 0, "", false, 9999);
  assert.match(rendered, /above/);
  assert.match(rendered, /q Quit/);
});

test("the preview scroll hint appears only when there is more to see", () => {
  const short = frame([reviewItem(attention({ summary: "brief" }), VIEWER)]);
  assert.ok(!short.includes("^u/^d"));
  const long = frame([
    reviewItem(attention({ summary: "long. ".repeat(400) }), VIEWER),
  ]);
  assert.match(long, /\^u\/\^d Preview/);
});

test("the footer offers browser and acknowledge", () => {
  const rendered = frame([reviewItem(attention(), VIEWER)]);
  assert.match(rendered, /b Browser/);
  assert.match(rendered, /x Acknowledge/);
});

test("subtabs read Reviews and Worktrees", () => {
  assert.match(
    frame([reviewItem(attention(), VIEWER)]),
    /Reviews {2}│ {2}Worktrees/,
  );
});

test("search still ranks and reports its count", () => {
  const item = reviewItem(attention(), VIEWER);
  assert.equal(rankDashboardItems([item], "reviewer").length, 1);
  assert.equal(rankDashboardItems([item], "does-not-match").length, 0);
  assert.match(
    frame([item], {}, 0, "reviewer", true),
    /\/reviewer · 1\/1 matches/,
  );
});
