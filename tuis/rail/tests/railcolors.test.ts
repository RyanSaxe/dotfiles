// The compact rail's colour contract. The rail is narrow, so attention
// colour must sit on the first stable token — the one that survives
// truncation — and never on text that gets clipped or on the timer.

import assert from "node:assert/strict";
import { test } from "node:test";

import { reviewRows } from "../src/sections/review.js";
import { elsewhereRows } from "../src/sections/elsewhere.js";
import type { ReviewSnapshot } from "../src/attention/review.js";
import type { Agent } from "../src/data.js";
import type { AttentionItem } from "../src/attention/types.js";
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

const item = (over: Partial<AttentionItem> = {}): AttentionItem => ({
  id: "x",
  kind: "conversation",
  targetKind: "pull_request",
  repository: "owner/project",
  number: 12,
  title: "t",
  url: "u",
  summary: "SUMMARYTEXT",
  actor: { login: "a", kind: "user" },
  createdAt: new Date(Date.now() - 90_000_000).toISOString(),
  priority: "normal",
  ...over,
});

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
  const ci = reviewRows(snapshot([item({ kind: "ci" })]), palette, 40)
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
