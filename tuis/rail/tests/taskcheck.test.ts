// The vault task surface: what the slab shows, what it refuses to show, what
// it says when there is no vault, and how a task becomes a dashboard row.
// Nothing here touches a real vault — the CLI is a fixture script, so the
// failure paths are exercised as the rail actually meets them.

import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";

import { rankDashboardItems, renderDashboard } from "../src/dashboard.js";
import type { DashboardData } from "../src/dashboard.js";
import type { RailData } from "../src/data.js";
import { renderRail } from "../src/render.js";
import { taskItem } from "../src/review-dashboard.js";
import { taskRows } from "../src/sections/tasks.js";
import {
  completeTask,
  hasOverdue,
  loadTaskSnapshot,
  parseTasks,
  railTasks,
  type TaskSnapshot,
  type TaskState,
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

// A whole rail with the Agents tab showing, so what the Tasks tab says about
// itself is the snapshot talking rather than the visible section.
const railData = (tasks: TaskSnapshot): RailData => ({
  session: "dotfiles",
  activeTab: "agents",
  windows: [],
  agents: [],
  review: {
    revision: 1,
    username: null,
    lastSuccessfulSyncAt: null,
    lastError: null,
    items: [],
    unacknowledged: [],
    acknowledged: new Set<string>(),
  },
  tasks,
  acked: new Set<string>(),
  hints: new Map<string, string>(),
  sprite: null,
  page: 0,
  prefixHeld: false,
});

test("due state is the only hue the slab spends", () => {
  const rendered = taskRows(snapshot(SPREAD), palette, 26)
    .map((line) => line.text)
    .join("\n");
  const shade = (color: string): string =>
    hex(blend(color, railBg(palette), DIM_KEEP));
  assert.equal(colorOf(rendered, "overdue by a day"), shade(palette.red));
  assert.equal(colorOf(rendered, "due today"), shade(palette.peach));
  // Today and tomorrow are the pair a glance has to tell apart, so tomorrow
  // is yellow rather than a second peach row.
  assert.equal(colorOf(rendered, "due tomorrow"), shade(palette.yellow));
  assert.equal(colorOf(rendered, "a near thing"), shade(palette.mauve));
});

// The item rows, without the spacers between them and without colour.
const itemLines = (json: string, width = 26): string[] =>
  taskRows(snapshot(json), palette, width)
    .filter((line) => line.item)
    .map((line) => plain(line.text));

test("the slab is one urgency-ordered list, with no state labels", () => {
  const lines = itemLines(SPREAD);
  // No group headings: a row says its state in hue and in where it sits.
  for (const state of ["overdue", "today", "tomorrow", "near"]) {
    assert.ok(
      !taskRows(snapshot(SPREAD), palette, 26).some(
        (line) => !line.item && plain(line.text).trim() === state,
      ),
    );
  }
  // Urgency, then the calendar, then the text — the projection's order,
  // rendered top to bottom with nothing between the rows.
  railTasks(parseTasks(SPREAD)).forEach((task, index) => {
    assert.ok((lines[index] ?? "").includes(task.text.slice(0, 12)));
  });
  assert.equal(lines.length, railTasks(parseTasks(SPREAD)).length);
  // Later and undated work never reaches the slab, in any form.
  const rendered = lines.join("\n");
  assert.ok(!rendered.includes("due next month"));
  assert.ok(!rendered.includes("no date at all"));
  assert.ok(!rendered.includes("already done"));
});

test("a task row is an agent row: numbered pill, text, right span", () => {
  const lines = itemLines(SPREAD);
  // The same three-cell pill the window and elsewhere rows use, numbering
  // display positions: pill N is the Nth row of the slab's projection, which
  // is exactly what alt+space N opens.
  lines.forEach((line, index) => {
    assert.ok(line.startsWith(`\ue0b6${String(index + 1)}\ue0b4 `));
  });
  assert.match(lines[1] ?? "", /overdue by a day\s+08-21$/);
  // A date is the news for anything but today and tomorrow, where the day
  // itself is what the row has to say.
  assert.match(lines[2] ?? "", /due today\s+today$/);
  assert.match(lines[3] ?? "", /due tomorrow\s+tmr$/);
});

test("the digits stop at nine, and the text column does not move", () => {
  const many = output(
    Array.from({ length: 11 }, (_, index) =>
      row({
        id: `many:${String(index)}`,
        text: `task ${String(index).padStart(2, "0")}`,
      }),
    ),
  );
  const lines = itemLines(many);
  // Nine is what the tmux element table binds; the dashboard is the overflow
  // surface. A row past it keeps the pill's cells as air so the text column
  // holds all the way down the list.
  assert.ok((lines[8] ?? "").startsWith("\ue0b69\ue0b4 task 08"));
  assert.ok((lines[9] ?? "").startsWith("    task 09"));
  assert.equal(
    (lines[9] ?? "").indexOf("task"),
    (lines[8] ?? "").indexOf("task"),
  );
});

test("an overdue task is what turns the Tasks tab red", () => {
  // The flag is read from the snapshot, not from the tab you are looking at:
  // Agents is showing here and Tasks still has to say it.
  const scene = (json: string): string =>
    renderRail(railData(snapshot(json)), palette, 27, 24).join("\n");
  const overdue = output([row({ state: "overdue", due: "2026-08-18" })]);
  const calm = output([row({ state: "today" })]);
  assert.equal(colorOf(scene(overdue), "Tasks"), hex(palette.red));
  assert.equal(colorOf(scene(calm), "Tasks"), hex(palette.dim2));
  // A completed task is nobody's attention, whatever its date says.
  assert.equal(hasOverdue(parseTasks(overdue)), true);
  assert.equal(
    hasOverdue(parseTasks(output([row({ state: "overdue", done: true })]))),
    false,
  );
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

// ----- the dashboard row -------------------------------------------------

const task = (over: Partial<VaultTask> = {}): VaultTask => ({
  id: "projects/dotfiles/TODO.md:7",
  text: "Verify the review rail at the narrowest width",
  done: false,
  due: "2026-08-18",
  state: "overdue",
  project: "dotfiles",
  section: "feat/vault-rail",
  file: "projects/dotfiles/TODO.md",
  line: 7,
  ...over,
});

test("a task becomes a row in its own vocabulary", () => {
  const item = taskItem(task(), ["  - [ ] something else"]);
  // The heading is the note, the reference its line: together they are the
  // id the CLI recomputes, which is also the panel's title.
  assert.equal(item.repository, "projects/dotfiles/TODO.md");
  assert.equal(item.reference, ":7");
  assert.equal(`${item.repository}${item.reference}`, item.id);
  assert.equal(item.from, "overdue");
  assert.equal(item.author, "feat/vault-rail");
  assert.equal(item.reason, "Verify the review rail at the narrowest width");
  assert.deepEqual(item.metadata, [{ text: "dotfiles", tone: "muted" }]);
  assert.equal(item.time, "08-18");
  assert.equal(item.url, null);
  assert.equal(item.preview.headline, "Overdue since 2026-08-18");
  assert.deepEqual(item.preview.body, ["  - [ ] something else"]);
  assert.ok(item.preview.context.includes("section feat/vault-rail"));
  assert.ok(item.preview.context.includes("file projects/dotfiles/TODO.md:7"));
});

test("the due-state hues carry over to the dashboard", () => {
  const tone = (state: TaskState): string => taskItem(task({ state })).tone;
  assert.equal(tone("overdue"), "overdue");
  assert.equal(tone("today"), "due_today");
  assert.equal(tone("tomorrow"), "due_tomorrow");
  assert.equal(tone("near"), "due_near");
  // Later and undated work is real, but it is not urgent.
  assert.equal(tone("later"), "neutral");
  assert.equal(tone("none"), "neutral");
});

test("the dashboard spends the same four hues on the same four states", () => {
  const states: TaskState[] = ["overdue", "today", "tomorrow", "near"];
  const frame = renderDashboard(
    {
      surface: "tasks",
      items: states.map((state, index) =>
        taskItem(
          task({ id: `t:${String(index)}`, state, text: `${state} row` }),
        ),
      ),
      status: "4 open",
      emptyMessage: "No open tasks",
      error: null,
    },
    0,
    palette,
    120,
    40,
  );
  assert.equal(colorOf(frame, "overdue row"), hex(palette.red));
  assert.equal(colorOf(frame, "today row"), hex(palette.peach));
  assert.equal(colorOf(frame, "tomorrow row"), hex(palette.yellow));
  assert.equal(colorOf(frame, "near row"), hex(palette.mauve));
});

const data = (): DashboardData => ({
  surface: "tasks",
  items: [
    taskItem(task()),
    taskItem(
      task({
        id: "inbox.md:3",
        file: "inbox.md",
        line: 3,
        text: "Read that paper",
        due: "2026-09-30",
        state: "later",
        project: null,
        section: null,
      }),
    ),
  ],
  status: "2 open · 1 overdue",
  emptyMessage: "No open tasks",
  error: null,
});

test("the table names task columns rather than review ones", () => {
  const frame = plain(renderDashboard(data(), 0, palette, 120, 40));
  assert.match(frame, /Line\s+State\s+Section\s+Task\s+Project\s+Due/);
  assert.ok(!frame.includes("Needs you"));
  // One view: there are no task workspaces to switch to.
  assert.ok(!frame.includes("Worktrees"));
  assert.match(frame, /x Complete/);
});

test("due state is searchable, because it is a cell and not only a colour", () => {
  const matched = rankDashboardItems(data().items, "overdue");
  assert.equal(matched.length, 1);
  assert.equal(matched[0]?.item.id, "projects/dotfiles/TODO.md:7");
});

test("a failed read reaches the dashboard as its empty message", () => {
  const frame = plain(
    renderDashboard(
      { ...data(), items: [], emptyMessage: "vault is not on PATH" },
      0,
      palette,
      120,
      40,
    ),
  );
  assert.match(frame, /vault is not on PATH/);
});
