// Exercises the pure review-to-dashboard mapping and the shared dashboard
// renderer without opening a terminal or contacting GitHub.

import assert from "node:assert/strict";
import { test } from "node:test";

import { rankDashboardItems, renderDashboard } from "../src/dashboard.js";
import type { DashboardData, DashboardItem } from "../src/dashboard.js";
import { reviewItem } from "../src/review-dashboard.js";
import type { AttentionItem, AttentionReason } from "../src/attention/types.js";
import type { Palette } from "../src/theme.js";

const VIEWER = "ryansaxe";

type AttentionOverrides = Partial<
  Omit<AttentionItem, "activityKey" | "reasons">
> & { reason?: Partial<AttentionReason> };

const attention = (over: AttentionOverrides = {}): AttentionItem => {
  const { reason: reasonOverride, ...itemOverride } = over;
  const reason: AttentionReason = {
    id: "comment:fixture",
    kind: "comment",
    summary: "Please take another look",
    actor: { login: "reviewer", kind: "user" },
    createdAt: "2026-08-19T16:00:00Z",
    priority: "normal",
    ...reasonOverride,
  };
  return {
    id: "pull_request:example/repo#7",
    targetKind: "pull_request",
    repository: "example/repo",
    number: 7,
    title: "Improve the review seam",
    context: {
      body: "## Summary\n\nKeep the dashboard context useful and concise.",
      author: { login: VIEWER, kind: "user" },
      ciState: "SUCCESS",
      failingChecks: [],
      additions: 603,
      deletions: 5,
      changedFiles: 14,
      labels: [],
    },
    url: "https://github.com/example/repo/pull/7",
    reasons: [reason],
    activityKey: reason.id,
    ...itemOverride,
  };
};

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
  diffAdd: "#60a474",
  diffDelete: "#c16771",
  diffChange: "#6197cd",
  mauve: "#cba6f7",
  peach: "#fab387",
  green: "#a6e3a1",
  red: "#f38ba8",
  statusWorking: "#cba6f7",
  statusWaiting: "#fab387",
  statusDone: "#a6e3a1",
};

// Rows are placed with absolute cursor positioning rather than newlines, so
// a frame has to be turned back into lines before it can be read.
const strip = (text: string): string =>
  text
    .replace(/\x1b\[\d+;1H/g, "\n")
    .replace(/\x1b\[[0-9;?]*[ -/]*[@-~]/g, "")
    .replace(/^\n/, "");

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
      120,
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

  const ci = reviewItem(
    attention({ reason: { kind: "ci", actor: null } }),
    VIEWER,
  );
  assert.equal(ci.from, "—");
  assert.equal(ci.author, "@ryansaxe");
});

test("tone follows the object, not the severity", () => {
  assert.equal(
    reviewItem(attention({ reason: { kind: "ci" } }), VIEWER).tone,
    "ci",
  );
  assert.equal(reviewItem(attention(), VIEWER).tone, "pull_request");
});

test("the reason phrase never repeats the actor", () => {
  const item = reviewItem(attention(), VIEWER);
  assert.equal(item.reason, "Commented on your PR");
  assert.ok(!item.reason.includes("reviewer"));
});

test("markdown is stripped from preview bodies", () => {
  const item = reviewItem(
    attention({ reason: { kind: "ci", actor: null } }),
    VIEWER,
  );
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

test("every rendered line fills the frame, bar the last by one column", () => {
  // The panel border is placed by reserving inner width. Get that wrong and
  // each preview row ends in a stray │, which is what shipped before.
  //
  // The last line stops one column short on purpose: writing into the
  // bottom-right cell makes a terminal advance, which scrolls the frame and
  // takes the header with it.
  const lines = frame([reviewItem(attention(), VIEWER)]).split("\n");
  lines.slice(0, -1).forEach((line) => assert.equal(line.length, 120));
  assert.equal(lines.at(-1)?.length, 119);
});

test("a long body cannot push the footer off the frame", () => {
  const long = attention({
    reason: { summary: "wall of text. ".repeat(400) },
  });
  const rendered = frame([reviewItem(long, VIEWER)]);
  assert.equal(rendered.split("\n").length, 24);
  assert.match(rendered, /q Quit/);
  assert.match(rendered, /more lines/);
});

test("scrolling past the end clamps instead of blanking the panel", () => {
  const long = attention({ reason: { summary: "paragraph. ".repeat(400) } });
  const rendered = frame([reviewItem(long, VIEWER)], {}, 0, "", false, 9999);
  assert.match(rendered, /above/);
  assert.match(rendered, /q Quit/);
});

test("the preview scroll hint appears only when there is more to see", () => {
  const short = frame([
    reviewItem(attention({ reason: { summary: "brief" } }), VIEWER),
  ]);
  assert.ok(!short.includes("^u/^d"));
  const long = frame([
    reviewItem(
      attention({ reason: { summary: "long. ".repeat(400) } }),
      VIEWER,
    ),
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

test("a pull request is sized by its diff, an issue by its labels", () => {
  const pr = reviewItem(attention(), VIEWER);
  assert.deepEqual(
    pr.metadata.map((span) => span.text),
    ["+603", " ", "-5", " ", "14f"],
  );
  assert.deepEqual(
    pr.metadata.filter((span) => span.tone !== "muted").map((s) => s.tone),
    ["add", "delete", "change"],
  );

  const issue = reviewItem(
    attention({
      targetKind: "issue",
      context: {
        body: "b",
        author: null,
        ciState: "UNKNOWN",
        failingChecks: [],
        additions: 0,
        deletions: 0,
        changedFiles: 0,
        labels: ["enhancement", "bug", "extra"],
      },
    }),
    VIEWER,
  );
  assert.deepEqual(
    issue.metadata.map((span) => span.text),
    ["enhancement bug"],
  );
});

test("state written before diff stats existed shows an empty cell", () => {
  const legacy = reviewItem(
    attention({
      context: {
        body: "b",
        author: null,
        ciState: "UNKNOWN",
        failingChecks: [],
      } as never,
    }),
    VIEWER,
  );
  assert.deepEqual(legacy.metadata, []);
});

test("a repository is grouped once, however the items are ordered", () => {
  // Items arrive in urgency order, which interleaves repositories. Grouping
  // on "did the repository change" printed the same heading several times.
  const rendered = frame([
    reviewItem(attention({ id: "a", repository: "one/alpha" }), VIEWER),
    reviewItem(attention({ id: "b", repository: "two/beta" }), VIEWER),
    reviewItem(
      attention({ id: "c", repository: "one/alpha", number: 8 }),
      VIEWER,
    ),
  ]);
  const headings = rendered
    .split("\n")
    .filter((line) => line.trim() === "one/alpha");
  assert.equal(headings.length, 1);
});

test("a long inbox cannot squeeze the preview to nothing", () => {
  const many = Array.from({ length: 60 }, (_, i) =>
    reviewItem(
      attention({ id: `i${i}`, number: i, repository: `org/repo${i % 3}` }),
      VIEWER,
    ),
  );
  const rendered = frame(many);
  // The selected item's headline must survive a full table.
  assert.match(rendered, /commented on repo0#0/);
  assert.match(rendered, /q Quit/);
  assert.equal(rendered.split("\n").length, 24);
});

test("row numbers stay sequential once rows are grouped", () => {
  // Ranking is by urgency, which interleaves repositories. If the numbers
  // came from that order they would skip — 25, 27, 28, 30 — and they are
  // jump targets, so they have to read as a sequence.
  const items = Array.from({ length: 9 }, (_, i) =>
    reviewItem(
      attention({ id: `i${i}`, number: i, repository: `org/repo${i % 3}` }),
      VIEWER,
    ),
  );
  const numbers = frame(items)
    .split("\n")
    .map((line) => /^[▌ ](\d+)\s/.exec(line)?.[1])
    .filter((value): value is string => value !== undefined)
    .map(Number);
  assert.ok(numbers.length >= 5);
  assert.equal(numbers[0], 1);
  for (let index = 1; index < numbers.length; index += 1) {
    assert.equal(
      numbers[index],
      (numbers[index - 1] ?? 0) + 1,
      `numbers must not skip: ${numbers.join(", ")}`,
    );
  }
});

test("the group heading is carried into a window that starts mid-group", () => {
  const items = Array.from({ length: 40 }, (_, i) =>
    reviewItem(
      attention({ id: `i${i}`, number: i, repository: "org/only" }),
      VIEWER,
    ),
  );
  const rendered = frame(items, {}, 30);
  assert.match(rendered, /org\/only/);
  assert.match(rendered, /above/);
});

test("the selected row survives at the bottom of a long list", () => {
  const items = Array.from({ length: 40 }, (_, i) =>
    reviewItem(
      attention({ id: `i${i}`, number: i, repository: `org/repo${i % 2}` }),
      VIEWER,
    ),
  );
  const rendered = frame(items, {}, 39);
  assert.match(rendered, /▌40\s/);
});

test("the overflow line says which direction the rest is in", () => {
  const items = Array.from({ length: 40 }, (_, i) =>
    reviewItem(
      attention({ id: `i${i}`, number: i, repository: "org/only" }),
      VIEWER,
    ),
  );
  assert.match(frame(items, {}, 0), /↓ \d+ below/);
  assert.match(frame(items, {}, 39), /↑ \d+ above/);
});

test("the Worktrees view relabels its columns and its keys", () => {
  const workspace: DashboardItem = {
    id: "/w/pr-3",
    repository: "owner/project",
    reference: "#3",
    from: "open",
    author: "clean",
    authorIsViewer: true,
    reason: "test-pr-1",
    metadata: [],
    time: "",
    title: "test-pr-1",
    url: null,
    tone: "neutral",
    preview: {
      headline: "project#3 · test-pr-1",
      bullets: [],
      body: [],
      context: ["clean — safe to clean up"],
    },
  };
  const rendered = strip(
    renderDashboard(
      {
        surface: "reviews",
        items: [workspace],
        status: "1 workspace · 1 open",
        emptyMessage: "No pull request is checked out locally",
        error: null,
      },
      0,
      palette,
      120,
      24,
      "",
      false,
      0,
      "worktrees",
    ),
  );
  assert.match(rendered, /Session {2}/);
  assert.match(rendered, /Changes/);
  assert.match(rendered, /Pull request/);
  // Enter focuses a workspace rather than opening one, and cleanup is
  // deliberately a capital so it cannot be hit by accident.
  assert.match(rendered, /↵ Focus/);
  assert.match(rendered, /X Clean up/);
  assert.ok(!rendered.includes("Needs you"));
});

test("a narrow frame drops footer keys instead of clipping a word", () => {
  const rendered = strip(
    renderDashboard(
      {
        surface: "reviews",
        items: [reviewItem(attention(), VIEWER)],
        status: "1 needs you",
        emptyMessage: "",
        error: null,
      },
      0,
      palette,
      70,
      24,
    ),
  );
  const footer = rendered.split("\n").at(-1) ?? "";
  assert.equal(footer.length, 69);
  // Whatever survives, quitting and navigating always do.
  assert.match(footer, /q Quit/);
  assert.match(footer, /↑↓ Navigate/);
});

test("assisted review is its own key, never the normal open", () => {
  const rendered = frame([reviewItem(attention(), VIEWER)]);
  assert.match(rendered, /a Assisted/);
  // Enter must stay the plain human path: nothing about it says agent.
  assert.match(rendered, /↵ Open/);
});
