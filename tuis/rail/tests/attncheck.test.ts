// Exercises the attention-routing decisions: presence and which agents
// ride a phone ping (transitions vs departure sweep). Terminal focus is
// tmux's own client_flags now, exercised by ackcheck.
//
//   npm test

import assert from "node:assert/strict";

import {
  AGENT_STATUS_LAG_SECS,
  stabilizeAgents,
  type StableAgentState,
  type Agent,
  type AgentStatus,
} from "../src/data.js";
import { attentionLevel, phoneBatch } from "../src/notifications.js";
import { isPresent } from "../src/probes.js";

const agent = (
  paneId: string,
  status: AgentStatus,
  updatedTs = 100,
): Agent => ({
  session: "s",
  windowName: paneId,
  paneId,
  status,
  title: "t",
  elapsedSecs: 5,
  updatedTs,
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

// ----- status stabilization ---------------------------------------------
// Boundaries are derived from the constant, never restated: a test that
// spells out the window is a second copy of it, and the two drift.
const CHANGED_AT = 100;
const stableStatuses = new Map<string, StableAgentState>([
  ["%1", { status: "working", updatedTs: 90 }],
]);
const waitingChange = agent("%1", "waiting", CHANGED_AT);
assert.equal(
  stabilizeAgents(
    [waitingChange],
    stableStatuses,
    CHANGED_AT + AGENT_STATUS_LAG_SECS - 1,
  )[0]?.status,
  "working",
  "a status change stays provisional right up to the window",
);
assert.equal(
  stabilizeAgents(
    [waitingChange],
    stableStatuses,
    CHANGED_AT + AGENT_STATUS_LAG_SECS - 1,
  )[0]?.updatedTs,
  90,
  "a provisional status keeps the accepted status timestamp",
);
assert.equal(
  stabilizeAgents(
    [waitingChange],
    stableStatuses,
    CHANGED_AT + AGENT_STATUS_LAG_SECS,
  )[0]?.status,
  "waiting",
  "a status that lasts the full window is accepted",
);
assert.equal(
  stabilizeAgents(
    [waitingChange],
    stableStatuses,
    CHANGED_AT + AGENT_STATUS_LAG_SECS,
  )[0]?.updatedTs,
  CHANGED_AT,
  "the accepted status carries its own event timestamp",
);
const doneChange = agent("%1", "done", CHANGED_AT + AGENT_STATUS_LAG_SECS + 1);
assert.equal(
  stabilizeAgents(
    [doneChange],
    stableStatuses,
    CHANGED_AT + AGENT_STATUS_LAG_SECS + 2,
  )[0]?.status,
  "waiting",
  "every status gets the same stabilization window",
);
// The window is only meaningful in multiples of the sampling interval: the
// daemon re-reads agents every 5s, so anything at or below that suppresses
// nothing at all.
assert.ok(
  AGENT_STATUS_LAG_SECS > 5,
  "the stabilization window must exceed the agent reconcile interval",
);
assert.equal(
  stabilizeAgents(
    [doneChange],
    stableStatuses,
    doneChange.updatedTs + AGENT_STATUS_LAG_SECS,
  )[0]?.status,
  "done",
  "the latest stable status replaces the previous one",
);

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

// ----- the two channels are deliberately different ----------------------
// The bar reads an ACK-FILTERED level; the phone reads raw TRANSITIONS.
// An acked agent must go quiet on the bar while a fresh transition still
// pings — collapsing these into one path is a plausible-looking
// "simplification" that would silently break one of them.
const ackedWaiting = new Set(["%1"]);
assert.equal(
  attentionLevel([waiting], ackedWaiting),
  "none",
  "visiting an agent clears the bar",
);
assert.deepEqual(
  phoneBatch([waiting], [waiting], ackedWaiting, false, false),
  [waiting],
  "...but a transition still pings the phone",
);
assert.equal(
  attentionLevel([waiting, done], none),
  "waiting",
  "waiting outranks done",
);
assert.equal(
  attentionLevel([working], none),
  "none",
  "working is information, not attention",
);
