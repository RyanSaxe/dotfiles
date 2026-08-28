// Exercises the attention-routing decisions: presence and which agents
// ride a phone ping (transitions vs departure sweep). Terminal focus is
// tmux's own client_flags now, exercised by ackcheck.
//
//   npm test

import assert from "node:assert/strict";
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { acknowledgedPaneIds } from "../src/acks.js";
import {
  AGENT_STATUS_LAG_SECS,
  loadStatusTransitionTimes,
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
  statusTs = 100,
  updatedTs = statusTs,
): Agent => ({
  session: "s",
  windowName: paneId,
  paneId,
  status,
  statusTs,
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
const workmuxAgentsDir = mkdtempSync(join(tmpdir(), "rail-workmux-agents-"));
writeFileSync(
  join(workmuxAgentsDir, "agent.json"),
  JSON.stringify({
    pane_key: { pane_id: "%state-file" },
    status_ts: CHANGED_AT,
    updated_ts: 10_000,
  }),
);
assert.deepEqual(
  loadStatusTransitionTimes(workmuxAgentsDir),
  new Map([["%state-file", CHANGED_AT]]),
  "status age comes from Workmux's state-file transition timestamp",
);
const stableStatuses = new Map<string, StableAgentState>([
  ["%1", { status: "working", statusTs: 90 }],
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
  CHANGED_AT,
  "a provisional status keeps the current update timestamp",
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
  )[0]?.statusTs,
  CHANGED_AT,
  "the accepted status carries its own transition timestamp",
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
    doneChange.statusTs + AGENT_STATUS_LAG_SECS,
  )[0]?.status,
  "done",
  "the latest stable status replaces the previous one",
);

const heartbeatStatuses = new Map<string, StableAgentState>([
  ["%heartbeat", { status: "working", statusTs: 90 }],
]);
const heartbeatWaiting = agent("%heartbeat", "waiting", CHANGED_AT, 10_000);
assert.equal(
  stabilizeAgents(
    [heartbeatWaiting],
    heartbeatStatuses,
    CHANGED_AT + AGENT_STATUS_LAG_SECS,
  )[0]?.status,
  "waiting",
  "stability uses status transition age, not the heartbeat timestamp",
);

const transientStatuses = new Map<string, StableAgentState>([
  ["%transient", { status: "working", statusTs: 90 }],
]);
const transientWaiting = agent("%transient", "waiting", 300, 9_999);
assert.equal(
  stabilizeAgents(
    [transientWaiting],
    transientStatuses,
    300 + AGENT_STATUS_LAG_SECS - 1,
  )[0]?.status,
  "working",
  "a fresh waiting classification stays provisional",
);
const resumed = agent("%transient", "working", 301, 10_000);
assert.equal(
  stabilizeAgents([resumed], transientStatuses, 301)[0]?.status,
  "working",
  "returning to working discards transient waiting immediately",
);
assert.deepEqual(transientStatuses.get("%transient"), {
  status: "working",
  statusTs: 301,
});

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
  "departure sweeps active done/waiting notifications, never working",
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

// ----- the two channels share the active notification projection ----------
// Acknowledging a transition quiets every attention surface. A later
// transition gets a new timestamp and becomes active again.
const ackedWaiting = new Set(["%1"]);
assert.equal(
  attentionLevel([waiting], ackedWaiting),
  "none",
  "visiting an agent clears the bar",
);
assert.deepEqual(
  phoneBatch([waiting], [waiting], ackedWaiting, false, false),
  [],
  "an acknowledged transition does not ping the phone",
);
const laterWaiting = agent("%1", "waiting", 300);
const laterAcked = acknowledgedPaneIds([laterWaiting], { "%1": 100 });
assert.equal(
  attentionLevel([laterWaiting], laterAcked),
  "waiting",
  "a later transition reactivates attention after acknowledgement",
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
