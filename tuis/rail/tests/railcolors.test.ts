// The compact rail's colour contract. The rail is narrow, so attention
// colour must sit on the first stable token — the one that survives
// truncation — and never on text that gets clipped or on the timer.

import assert from "node:assert/strict";
import { test } from "node:test";

import { assignHints } from "../src/hints.js";
import { reviewRows } from "../src/sections/review.js";
import { elsewhereRows } from "../src/sections/elsewhere.js";
import { sortByUrgency } from "../src/sections/rows.js";
import type { ReviewSnapshot } from "../src/attention/review.js";
import type { Agent } from "../src/data.js";
import type { AttentionItem, AttentionReason } from "../src/attention/types.js";
import type { Palette } from "../src/theme.js";
import { blend, DIM_KEEP, railBg } from "../src/theme.js";

const palette: Palette = {
  mode: "dark",
  accent: "#d8b44a",
  notify: "#69ceea",
  base: "#1e1e2e",
  crust: "#11111b",
  surface0: "#313244",
  text: "#cdd6f4",
  dim: "#6c7086",
  dim2: "#9399b2",
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

const hex = (color: string): string => {
  const n = parseInt(color.slice(1), 16);
  return `38;2;${(n >> 16) & 0xff};${(n >> 8) & 0xff};${n & 0xff}`;
};

// Colour of the run of text containing `needle`.
const colorOf = (rendered: string, needle: string): string | null => {
  const parts = rendered.split("\x1b[");
  let current: string | null = null;
  for (const part of parts) {
    const match = /^(38;2;\d+;\d+;\d+)m([\s\S]*)$/.exec(part);
    if (match) {
      current = match[1] ?? null;
      if ((match[2] ?? "").includes(needle)) return current;
    }
  }
  return null;
};

const dimmed = hex(blend(palette.dim, railBg(palette), DIM_KEEP));

type AttentionOverrides = Partial<
  Omit<AttentionItem, "activityKey" | "reasons">
> & { reason?: Partial<AttentionReason> };

const item = (over: AttentionOverrides = {}): AttentionItem => {
  const { reason: reasonOverride, ...itemOverride } = over;
  const reason: AttentionReason = {
    id: "comment:fixture",
    kind: "comment",
    summary: "SUMMARYTEXT",
    actor: { login: "a", kind: "user" },
    createdAt: new Date(Date.now() - 90_000_000).toISOString(),
    priority: "normal",
    ...reasonOverride,
  };
  return {
    id: "pull_request:owner/project#12",
    targetKind: "pull_request",
    repository: "owner/project",
    number: 12,
    title: "t",
    url: "u",
    reasons: [reason],
    activityKey: reason.id,
    ...itemOverride,
  };
};

const snapshot = (items: AttentionItem[]): ReviewSnapshot => ({
  revision: 1,
  username: "ryansaxe",
  lastSuccessfulSyncAt: null,
  lastError: null,
  items,
  unacknowledged: items,
  acknowledged: new Set(),
});

test("review colour sits on repository#number, not the summary", () => {
  const rendered = reviewRows(snapshot([item()]), palette, 40)
    .map((row) => row.text)
    .join("\n");
  assert.equal(
    colorOf(rendered, "project#12"),
    hex(blend(palette.peach, railBg(palette), DIM_KEEP)),
  );
  assert.equal(colorOf(rendered, "SUMMARYTEXT"), dimmed);
});

test("CI is red and issue activity is mauve", () => {
  const ci = reviewRows(
    snapshot([item({ reason: { kind: "ci" } })]),
    palette,
    40,
  )
    .map((r) => r.text)
    .join("\n");
  assert.equal(
    colorOf(ci, "project#12"),
    hex(blend(palette.red, railBg(palette), DIM_KEEP)),
  );
  const issue = reviewRows(
    snapshot([item({ targetKind: "issue" })]),
    palette,
    40,
  )
    .map((r) => r.text)
    .join("\n");
  assert.equal(
    colorOf(issue, "project#12"),
    hex(blend(palette.mauve, railBg(palette), DIM_KEEP)),
  );
});

const agent = (over: Partial<Agent> = {}): Agent => ({
  session: "proj",
  windowName: "w",
  paneId: "%1",
  status: "waiting",
  statusTs: 0,
  title: "t",
  elapsedSecs: 30 * 60 * 60,
  updatedTs: 0,
  worktree: "featurebranch",
  branch: "featurebranch",
  ...over,
});

test("agent colour sits on the leading project/ token", () => {
  const rendered = elsewhereRows([agent()], new Set(), new Map(), palette, 40)
    .map((row) => row.text)
    .join("\n");
  assert.equal(
    colorOf(rendered, "proj/"),
    hex(blend(palette.statusWaiting, railBg(palette), DIM_KEEP)),
  );
  assert.equal(colorOf(rendered, "featurebranch"), dimmed);
});

test("acknowledged waiting stays quiet while its live status remains waiting", () => {
  const rendered = elsewhereRows(
    [agent()],
    new Set(["%1"]),
    new Map(),
    palette,
    40,
  )
    .map((row) => row.text)
    .join("\n");
  assert.equal(
    colorOf(rendered, "proj/"),
    hex(blend(palette.dim2, railBg(palette), DIM_KEEP)),
  );
});

test("an ancient timer is still dim — age never escalates severity", () => {
  // 30 hours is well past the eight-hour mark that used to turn the timer
  // full red. fmtElapsed renders it as "1d".
  const rendered = elsewhereRows([agent()], new Set(), new Map(), palette, 40)
    .map((row) => row.text)
    .join("\n");
  const red = hex(blend(palette.red, railBg(palette), DIM_KEEP));
  assert.notEqual(colorOf(rendered, "1d"), red);
  assert.equal(colorOf(rendered, "1d"), dimmed);
});

// Eleven agents in other sessions, most recent first, so the elsewhere list
// runs past the nine digits the tmux element table binds.
const crowd = (): Agent[] =>
  Array.from({ length: 11 }, (_, index) =>
    agent({
      session: `proj${String(index).padStart(2, "0")}`,
      paneId: `%${String(index + 1)}`,
      statusTs: 100 - index,
      updatedTs: 100 - index,
    }),
  );

const plain = (text: string): string =>
  text.replace(/\x1b\[[0-9;?]*[ -/]*[@-~]/g, "");

// The pill's number, for a row that has one.
const pillNumber = (row: string): string | undefined =>
  /^\ue0b6(\d+)\ue0b4 /.exec(row)?.[1];

const elsewhereLines = (agents: Agent[], width = 40): string[] => {
  const hints = assignHints(agents, ["viewer"], new Set()).get("viewer");
  return elsewhereRows(agents, new Set(), hints ?? new Map(), palette, width)
    .filter((row) => row.item)
    .map((row) => plain(row.text));
};

test("every elsewhere row is numbered, and 1-9 are the jump digits", () => {
  const agents = crowd();
  const hints = assignHints(agents, ["viewer"], new Set()).get("viewer");
  const lines = elsewhereLines(agents);
  sortByUrgency(agents, new Set()).forEach((entry, index) => {
    const number = pillNumber(lines[index] ?? "");
    // The invariant: where a digit exists, the pill IS that digit — pressing
    // it lands on this row's pane and no other.
    if (index < 9) assert.equal(number, hints?.get(entry.paneId));
    else assert.equal(hints?.get(entry.paneId), undefined);
    assert.equal(number, String(index + 1));
  });
  // Past the ninth there is no key left to hand out, but the list keeps
  // counting rather than trailing off into blank pills.
  assert.equal(pillNumber(lines[9] ?? ""), "10");
  assert.equal(pillNumber(lines[10] ?? ""), "11");
});

test("a two-digit pill costs the worktree name a cell, never the timer", () => {
  for (const width of [40, 26]) {
    for (const line of elsewhereLines(crowd(), width)) {
      assert.equal(Array.from(line).length, width);
      assert.ok(line.endsWith("1d"), `${String(width)}: ${line}`);
    }
  }
});
