// The vault's tasks, as the rail reads them.
//
// `vault tasks --json` is the only reader and `vault task done` the only
// writer: the CLI owns the Markdown grammar, so nothing here parses or edits
// a note. Identity is `<vault-relative-path>:<line>`, recomputed by the CLI
// on every call — so it is never stored between refreshes. Every surface
// asks again and acts on what it just read.

import { execFile } from "node:child_process";
import { promisify } from "node:util";

const run = promisify(execFile);

// By name, never by path: the installed CLI is the one that knows where this
// machine's vault is.
const VAULT = "vault";

export type TaskState =
  "overdue" | "today" | "tomorrow" | "near" | "later" | "none";

export interface VaultTask {
  id: string;
  text: string;
  done: boolean;
  due: string | null;
  state: TaskState;
  project: string | null;
  section: string | null;
  file: string;
  line: number;
}

// Open tasks in urgency order, or the one line explaining why there are
// none. A machine with no vault is an ordinary state rather than a fault, so
// the failure travels as text a surface can render instead of an exception
// that would take the frame with it.
export interface TaskSnapshot {
  tasks: VaultTask[];
  error: string | null;
}

export function emptyTaskSnapshot(): TaskSnapshot {
  return { tasks: [], error: null };
}

// Urgency first, then the calendar, then the text. Both surfaces render this
// one order, so a row is where you last saw it.
const STATE_ORDER: Record<TaskState, number> = {
  overdue: 0,
  today: 1,
  tomorrow: 2,
  near: 3,
  later: 4,
  none: 5,
};

// The due states the rail slab itself shows: what is late, what today asks
// for, and what tomorrow will. Everything further out — near-term, later,
// undated — stays in the vault, the Tasks dashboard, and Neovim's picker.
// The sidebar is a glance, and a glance that carries next week is a list you
// stop reading.
const RAIL_STATES: ReadonlySet<TaskState> = new Set([
  "overdue",
  "today",
  "tomorrow",
]);

const STATES: ReadonlySet<string> = new Set(Object.keys(STATE_ORDER));

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isVaultTask(value: unknown): value is VaultTask {
  return (
    isRecord(value) &&
    typeof value["id"] === "string" &&
    typeof value["text"] === "string" &&
    typeof value["done"] === "boolean" &&
    (value["due"] === null || typeof value["due"] === "string") &&
    typeof value["state"] === "string" &&
    STATES.has(value["state"]) &&
    (value["project"] === null || typeof value["project"] === "string") &&
    (value["section"] === null || typeof value["section"] === "string") &&
    typeof value["file"] === "string" &&
    typeof value["line"] === "number"
  );
}

// The same rank, for a surface that holds rendered rows rather than tasks:
// the Tasks dashboard sorts its own items, and the state reaches it as the
// word in their State cell. One table ranks urgency everywhere.
export function stateRank(state: string): number {
  return state in STATE_ORDER
    ? STATE_ORDER[state as TaskState]
    : // Anything that is not a state sinks rather than jumps the queue.
      Object.keys(STATE_ORDER).length;
}

export function byUrgency(a: VaultTask, b: VaultTask): number {
  return (
    STATE_ORDER[a.state] - STATE_ORDER[b.state] ||
    (a.due ?? "").localeCompare(b.due ?? "") ||
    a.text.localeCompare(b.text)
  );
}

export function parseTasks(stdout: string): VaultTask[] {
  const parsed: unknown = JSON.parse(stdout);
  if (!Array.isArray(parsed)) throw new Error("vault tasks returned no list");
  return (
    parsed
      .filter(isVaultTask)
      // Completed tasks are dropped here rather than by each surface: there is
      // no reopen verb, so a finished task is not something anything acts on.
      .filter((task) => !task.done)
      .sort(byUrgency)
  );
}

// `MM-DD`, the one due-date shorthand both surfaces show. The year is never
// news for something due inside the week, and the slab is 26 cells wide.
export function shortDue(due: string | null): string {
  return due === null ? "" : due.slice(5);
}

export function railTasks(tasks: readonly VaultTask[]): VaultTask[] {
  return tasks.filter((task) => RAIL_STATES.has(task.state));
}

// The Tasks tab's attention flag: work whose date has already passed. Only
// incomplete tasks are ever in a snapshot, so an overdue one is always
// something still owed.
export function hasOverdue(tasks: readonly VaultTask[]): boolean {
  return tasks.some((task) => task.state === "overdue");
}

// The CLI already says exactly what is wrong — VAULT_DIR unset, a directory
// that is not there — in one line on stderr. Prefer its sentence to ours;
// only its absence needs words of our own.
function failureText(error: unknown): string {
  if (error instanceof SyntaxError) return "vault tasks: unreadable output";
  if (!(error instanceof Error)) return String(error);
  const stderr = (error as { stderr?: string }).stderr ?? "";
  const spoken = stderr
    .split("\n")
    .map((text) => text.trim())
    .find((text) => text !== "");
  if (spoken !== undefined) return spoken;
  if ((error as { code?: unknown }).code === "ENOENT") {
    return "vault is not on PATH";
  }
  return error.message.split("\n")[0] ?? "vault tasks failed";
}

export async function loadTaskSnapshot(command = VAULT): Promise<TaskSnapshot> {
  try {
    const { stdout } = await run(command, ["tasks", "--json"], {
      timeout: 10_000,
      // A vault is thousands of notes at most; the default 1MB cap is the
      // only thing here that scales with it.
      maxBuffer: 8 * 1024 * 1024,
    });
    return { tasks: parseTasks(stdout), error: null };
  } catch (error) {
    return { tasks: [], error: failureText(error) };
  }
}

// A stale id — the line moved between the read and the keystroke — comes
// back from the CLI as its own clear error rather than completing the wrong
// task silently.
export async function completeTask(id: string, command = VAULT): Promise<void> {
  try {
    await run(command, ["task", "done", id]);
  } catch (error) {
    throw new Error(failureText(error));
  }
}
