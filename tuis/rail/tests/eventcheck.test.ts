import assert from "node:assert/strict";

import {
  reconcileAttentionEvents,
  surfaceAttentionEvents,
  type AttentionEvents,
} from "../src/attention-events.js";
import type { Agent } from "../src/data.js";

const agent = (
  paneId: string,
  status: Agent["status"],
  updatedTs: number,
): Agent => ({
  session: "dotfiles",
  windowName: "codex",
  paneId,
  status,
  title: "dotfiles",
  elapsedSecs: 0,
  updatedTs,
  worktree: "dotfiles",
  branch: "develop",
});

const events: AttentionEvents = {};
const done = agent("%1", "done", 100);
const working = agent("%1", "working", 120);

assert.equal(
  reconcileAttentionEvents(events, [done], {}),
  true,
  "a stable completion becomes a durable event",
);
assert.deepEqual(events["%1"], { status: "done", updatedTs: 100 });

assert.equal(
  reconcileAttentionEvents(events, [working], {}),
  false,
  "working does not erase an unread completion",
);
assert.equal(
  surfaceAttentionEvents([working], events, {})[0]?.status,
  "done",
  "the unread completion stays visible while the agent resumes working",
);

assert.equal(
  reconcileAttentionEvents(events, [working], { "%1": 120 }),
  true,
  "a visit after publication clears the event",
);
assert.equal(events["%1"], undefined);

const shortDone: AttentionEvents = {};
const stabilizedWorking = agent("%2", "working", 220);
const rawDone = agent("%2", "done", 200);
assert.equal(
  reconcileAttentionEvents(shortDone, [stabilizedWorking], {}, [rawDone]),
  true,
  "a done event survives before the stabilizer accepts the next working state",
);
assert.deepEqual(shortDone["%2"], { status: "done", updatedTs: 200 });

const waitingCandidate: AttentionEvents = {};
const rawWaiting = agent("%3", "waiting", 300);
assert.equal(
  reconcileAttentionEvents(
    waitingCandidate,
    [agent("%3", "working", 300)],
    {},
    [rawWaiting],
  ),
  false,
  "a waiting candidate remains stabilization-gated",
);
assert.equal(waitingCandidate["%3"], undefined);
assert.equal(
  reconcileAttentionEvents(waitingCandidate, [rawWaiting], {}),
  true,
  "waiting becomes durable once the stabilized view accepts it",
);

assert.equal(
  reconcileAttentionEvents(shortDone, [], {}),
  true,
  "deleting a pane retires its unreachable event",
);
assert.equal(shortDone["%2"], undefined);

console.log("attention event checks passed");
