// Exercises the attention-routing decisions: presence, terminal focus,
// and which agents ride a phone ping (transitions vs departure sweep).
//
//   npx tsx dev/attncheck.ts

import assert from "node:assert/strict";

import { phoneBatch } from "../src/notifications.js";
import { isPresent, terminalFocused } from "../src/probes.js";
import type { Agent, AgentStatus } from "../src/data.js";

const agent = (paneId: string, status: AgentStatus): Agent => ({
  session: "s",
  windowName: paneId,
  paneId,
  status,
  title: "t",
  elapsedSecs: 5,
  updatedTs: 100,
  worktree: "s",
  branch: "main",
});

// ----- presence ----------------------------------------------------------
assert.equal(isPresent(30, null, 1000), true, "recent input is present");
assert.equal(isPresent(500, null, 1000), false, "stale input is away");
assert.equal(isPresent(null, 950, 1000), true, "fresh client activity");
assert.equal(isPresent(null, 100, 1000), false, "stale client activity");
assert.equal(isPresent(null, null, 1000), false, "no signal is away");
assert.equal(isPresent(30, 100, 1000), true, "input idle outranks clients");

// ----- terminal focus ----------------------------------------------------
assert.equal(terminalFocused("Ghostty"), true, "ghostty is the terminal");
assert.equal(terminalFocused("kitty"), true, "kitty is the terminal");
assert.equal(terminalFocused("Arc"), false, "a browser is not");
assert.equal(terminalFocused(null), true, "no signal keeps old behavior");

// ----- phone batch -------------------------------------------------------
const waiting = agent("%1", "waiting");
const done = agent("%2", "done");
const working = agent("%3", "working");
const all = [waiting, done, working];
const none = new Set<string>();

assert.deepEqual(
  phoneBatch([waiting], all, none, true, false),
  [],
  "present suppresses every ping",
);
assert.deepEqual(
  phoneBatch([waiting], all, none, false, false),
  [waiting],
  "away pings transitions",
);
assert.deepEqual(
  phoneBatch([], all, none, false, true),
  [waiting, done],
  "departure sweeps un-acked done/waiting, never working",
);
assert.deepEqual(
  phoneBatch([], all, new Set(["%1"]), false, true),
  [done],
  "acked agents stay out of the sweep",
);
assert.deepEqual(
  phoneBatch([waiting], all, none, false, true),
  [waiting, done],
  "a transitioning agent rides the sweep once",
);
assert.deepEqual(
  phoneBatch([], all, none, false, false),
  [],
  "staying away re-pings nothing",
);
console.log("attention routing ok");
