// Pre-coloured content — bat markdown, delta diffs — is passed through
// rather than re-coloured. These are the rules that keep it from breaking
// the layout around it.

import assert from "node:assert/strict";
import { test } from "node:test";

import {
  clipAnsi,
  renderDiffView,
  sanitizeAnsi,
  visibleWidth,
} from "../src/dashboard.js";
import type { Palette } from "../src/theme.js";

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

const GREEN = "\x1b[38;2;0;255;0m";

test("escapes occupy no columns", () => {
  assert.equal(visibleWidth(`${GREEN}abc\x1b[0m`), 3);
});

test("erase sequences are stripped, colour is kept", () => {
  // Delta ends lines with \x1b[0K, which erases to the right edge and would
  // wipe the padding and border drawn after it.
  assert.equal(sanitizeAnsi(`${GREEN}hi\x1b[0K`), `${GREEN}hi`);
  assert.equal(
    sanitizeAnsi("\x1b[2J\x1b[H\x1b[1mbold\x1b[0m"),
    "\x1b[1mbold\x1b[0m",
  );
});

test("clipping counts visible columns, never cuts an escape", () => {
  const clipped = clipAnsi(`${GREEN}abcdefghij\x1b[0m`, 4);
  assert.equal(visibleWidth(clipped), 4);
  assert.ok(clipped.startsWith(GREEN));
  assert.ok(clipped.endsWith("\x1b[0m"));
});

test("a line already inside the budget is untouched", () => {
  const line = `${GREEN}abc\x1b[0m`;
  assert.equal(clipAnsi(line, 40), line);
});

test("an over-long diff line cannot push the footer off the frame", () => {
  // Delta does not wrap long content lines even when given --width: a README
  // diff really does hand us 458-column lines.
  const long = `${GREEN}${"x".repeat(458)}\x1b[0m`;
  const frame = renderDiffView("repo#1", [long, "short"], 0, palette, 100, 20);
  const plain = frame.replace(/\x1b\[[0-9;?]*[ -/]*[@-~]/g, "");
  const lines = plain.split("\n");
  assert.equal(lines.length, 20);
  for (const line of lines)
    assert.ok(line.length <= 100, `line was ${line.length}`);
  assert.match(plain, /q Back/);
});

test("the diff view reports its position and returns rather than closing", () => {
  const many = Array.from({ length: 500 }, (_, i) => `line ${i}`);
  const frame = renderDiffView("repo#1", many, 100, palette, 100, 20).replace(
    /\x1b\[[0-9;?]*[ -/]*[@-~]/g,
    "",
  );
  assert.match(frame, /of 500/);
  assert.match(frame, /q Back/);
  assert.match(frame, /j\/k Scroll/);
});

test("scrolling past the end clamps", () => {
  const frame = renderDiffView(
    "repo#1",
    ["a", "b"],
    9999,
    palette,
    100,
    20,
  ).replace(/\x1b\[[0-9;?]*[ -/]*[@-~]/g, "");
  assert.match(frame, /repo#1/);
  assert.match(frame, /q Back/);
});
