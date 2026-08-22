// The vault task surface: what the slab shows, what it refuses to show, and
// what it says when there is no vault. Nothing here touches a real vault —
// the CLI is a fixture script, so the failure paths are exercised as the
// rail actually meets them.

import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";

import { taskRows } from "../src/sections/tasks.js";
import {
  completeTask,
  loadTaskSnapshot,
  parseTasks,
  railTasks,
  type VaultTask,
} from "../src/tasks.js";
import { blend, DIM_KEEP, railBg, type Palette } from "../src/theme.js";

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

const plain = (text: string): string =>
  text.replace(/\x1b\[\d+;1H/g, "\n").replace(/\x1b\[[0-9;?]*[ -/]*[@-~]/g, "");

const dimmed = hex(blend(palette.dim, railBg(palette), DIM_KEEP));

// One CLI row, in the shape `vault tasks --json` emits it. Untyped on
// purpose: the rail validates what it is handed rather than trusting it.
const row = (over: Record<string, unknown> = {}): Record<string, unknown> => ({
  id: "projects/dotfiles/TODO.md:7",
  text: "a task",
  done: false,
  due: "2026-08-22",
  state: "today",
  project: "dotfiles",
  section: "feat/vault-rail",
  file: "projects/dotfiles/TODO.md",
  line: 7,
  ...over,
});

const output = (rows: Array<Record<string, unknown>>): string =>
  JSON.stringify(rows, null, 2);

// A spread across every state the CLI can report, deliberately out of order.
const SPREAD = output([
  row({
    id: "a:1",
    text: "near later still",
    due: "2026-08-27",
    state: "near",
  }),
  row({ id: "a:2", text: "due next month", due: "2026-09-30", state: "later" }),
  row({
    id: "a:3",
    text: "overdue twice over",
    due: "2026-08-18",
    state: "overdue",
  }),
  row({ id: "a:4", text: "no date at all", due: null, state: "none" }),
  row({
    id: "a:5",
    text: "due tomorrow",
    due: "2026-08-23",
    state: "tomorrow",
  }),
  row({
    id: "a:6",
    text: "already done",
    due: "2026-08-18",
    state: "overdue",
    done: true,
  }),
  row({ id: "a:7", text: "due today", due: "2026-08-22", state: "today" }),
  row({
    id: "a:8",
    text: "overdue by a day",
    due: "2026-08-21",
    state: "overdue",
  }),
  row({ id: "a:9", text: "a near thing", due: "2026-08-27", state: "near" }),
]);

const ids = (tasks: readonly VaultTask[]): string[] =>
  tasks.map((task) => task.id);

test("open tasks come back in urgency, then calendar, then text order", () => {
  // Two tasks share 2026-08-27, so the text is what separates them — an
  // order a person can predict is the point, not the order the vault
  // happened to be walked in.
  assert.deepEqual(ids(parseTasks(SPREAD)), [
    "a:3",
    "a:8",
    "a:7",
    "a:5",
    "a:9",
    "a:1",
    "a:2",
    "a:4",
  ]);
});

test("a completed task is not a task any surface acts on", () => {
  // There is no reopen verb, so completion is the end of a task's life here.
  assert.ok(!ids(parseTasks(SPREAD)).includes("a:6"));
});

test("the slab shows only overdue, today, tomorrow and near", () => {
  assert.deepEqual(ids(railTasks(parseTasks(SPREAD))), [
    "a:3",
    "a:8",
    "a:7",
    "a:5",
    "a:9",
    "a:1",
  ]);
});

test("a row that is not a task row is dropped, the rest survive", () => {
  const mixed = output([
    row({ id: "good:1" }),
    row({ id: "bad:1", state: "someday" }),
    row({ id: "bad:2", line: "seven" }),
    { nothing: "like a task" },
  ]);
  assert.deepEqual(ids(parseTasks(mixed)), ["good:1"]);
});

const snapshot = (json: string) => ({ tasks: parseTasks(json), error: null });

test("due state is the only hue the slab spends", () => {
  const rendered = taskRows(snapshot(SPREAD), palette, 26)
    .map((line) => line.text)
    .join("\n");
  const shade = (color: string): string =>
    hex(blend(color, railBg(palette), DIM_KEEP));
  assert.equal(colorOf(rendered, "overdue by a day"), shade(palette.red));
  assert.equal(colorOf(rendered, "due today"), shade(palette.peach));
  assert.equal(colorOf(rendered, "due tomorrow"), shade(palette.peach));
  assert.equal(colorOf(rendered, "a near thing"), shade(palette.mauve));
});

test("every group states its due state in text, and the date rides along", () => {
  const rendered = plain(
    taskRows(snapshot(SPREAD), palette, 26)
      .map((line) => line.text)
      .join("\n"),
  );
  for (const state of ["overdue", "today", "tomorrow", "near"]) {
    assert.match(rendered, new RegExp(`^${state}\\s*$`, "m"));
  }
  assert.match(rendered, /08-21/);
  // Later and undated work never reaches the slab, in any form.
  assert.ok(!rendered.includes("due next month"));
  assert.ok(!rendered.includes("no date at all"));
  assert.ok(!rendered.includes("already done"));
});

test("rows keep the section's text column, and only informative dates", () => {
  const rendered = plain(
    taskRows(snapshot(SPREAD), palette, 26)
      .map((line) => line.text)
      .join("\n"),
  );
  // A task has no jump target, so the pill's three cells stay empty — the
  // text still starts where every other section's does.
  assert.match(rendered, /^ {4}overdue by a day\s+08-21\s*$/m);
  // Under "today" the date would only repeat the group label, so the row
  // spends those cells on the text instead.
  assert.match(rendered, /^ {4}due today\s*$/m);
});

test("a week with nothing due says so rather than showing an empty tab", () => {
  const empty = output([row({ state: "later", due: "2026-09-30" })]);
  const rendered = taskRows(snapshot(empty), palette, 26)
    .map((line) => line.text)
    .join("\n");
  assert.match(plain(rendered), /Nothing due/);
  assert.equal(
    colorOf(rendered, "Nothing due"),
    hex(blend(palette.green, railBg(palette), DIM_KEEP)),
  );
});

test("a vault this machine does not have degrades to the CLI's sentence", () => {
  const failed = { tasks: [], error: "VAULT_DIR is not set" };
  const rendered = taskRows(failed, palette, 40)
    .map((line) => line.text)
    .join("\n");
  assert.match(plain(rendered), /VAULT_DIR is not set/);
  // Dim, not red: a machine without a vault is a state, not an alarm.
  assert.equal(colorOf(rendered, "VAULT_DIR is not set"), dimmed);
});

// ----- the CLI seam ------------------------------------------------------

// A stand-in for the installed CLI, so every failure the rail has to survive
// can be produced on demand.
const fakeVault = (body: string): string => {
  const directory = mkdtempSync(join(tmpdir(), "rail-vault-"));
  const path = join(directory, "vault");
  writeFileSync(path, `#!/bin/sh\n${body}\n`, { mode: 0o755 });
  return path;
};

test("a vault CLI that is not installed is a message, not a crash", async () => {
  const snapshot = await loadTaskSnapshot(
    join(mkdtempSync(join(tmpdir(), "rail-vault-")), "absent"),
  );
  assert.deepEqual(snapshot.tasks, []);
  assert.equal(snapshot.error, "vault is not on PATH");
});

test("the CLI's own stderr line is what the surface says", async () => {
  const command = fakeVault(
    'echo "VAULT_DIR points at a missing directory: /nope" >&2\nexit 1',
  );
  const snapshot = await loadTaskSnapshot(command);
  assert.deepEqual(snapshot.tasks, []);
  assert.equal(
    snapshot.error,
    "VAULT_DIR points at a missing directory: /nope",
  );
});

test("output that is not JSON, and JSON that is not a list", async () => {
  assert.equal(
    (await loadTaskSnapshot(fakeVault("echo 'half a { json'"))).error,
    "vault tasks: unreadable output",
  );
  assert.equal(
    (await loadTaskSnapshot(fakeVault("echo '{}'"))).error,
    "vault tasks returned no list",
  );
});

test("a healthy CLI call yields the projection and no error", async () => {
  const directory = mkdtempSync(join(tmpdir(), "rail-vault-"));
  const json = join(directory, "tasks.json");
  writeFileSync(json, SPREAD);
  const command = fakeVault(`cat "${json}"`);
  const snapshot = await loadTaskSnapshot(command);
  assert.equal(snapshot.error, null);
  assert.deepEqual(ids(railTasks(snapshot.tasks)).slice(0, 2), ["a:3", "a:8"]);
});

test("completing a task is the CLI's business, and its refusal is ours", async () => {
  const directory = mkdtempSync(join(tmpdir(), "rail-vault-"));
  const seen = join(directory, "argv");
  await completeTask(
    "projects/dotfiles/TODO.md:7",
    fakeVault(`printf '%s ' "$@" > "${seen}"`),
  );
  assert.equal(
    readFileSync(seen, "utf8").trim(),
    "task done projects/dotfiles/TODO.md:7",
  );
  await assert.rejects(
    completeTask(
      "projects/dotfiles/TODO.md:7",
      fakeVault('echo "no task at projects/dotfiles/TODO.md:7" >&2\nexit 1'),
    ),
    /no task at projects\/dotfiles\/TODO.md:7/,
  );
});
