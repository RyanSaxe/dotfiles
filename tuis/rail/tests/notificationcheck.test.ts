// The live status and the attention projection are separate. These checks
// exercise the projection at the boundary consumed by the rail, Sketchybar,
// phone routing, and attention jumps.

import assert from "node:assert/strict";
import { mkdirSync, readFileSync } from "node:fs";
import { join } from "node:path";

import { acknowledgedPaneIds } from "../src/acks.js";
import type { Agent, AgentStatus } from "../src/data.js";
import { attentionCandidates } from "../src/jump-attention.js";
import {
  ATTENTION_FILE,
  ATTENTION_TARGETS_FILE,
  attentionLevel,
  publishAttention,
} from "../src/notifications.js";
import { XDG_STATE } from "../src/paths.js";

const agent = (
  paneId: string,
  status: AgentStatus,
  statusTs: number,
  updatedTs = statusTs,
): Agent => ({
  session: "s",
  windowName: paneId,
  paneId,
  status,
  statusTs,
  title: paneId,
  elapsedSecs: 5,
  updatedTs,
  worktree: "s",
  branch: "main",
});

const waiting = agent("%waiting", "waiting", 100, 10_000);
const done = agent("%done", "done", 200, 20_000);
const working = agent("%waiting", "working", 300, 30_000);
const acknowledged = acknowledgedPaneIds([waiting, done], {});

assert.deepEqual(
  [...acknowledged].sort(),
  [],
  "unvisited waiting/done transitions are active notifications",
);
assert.equal(
  attentionLevel([waiting, done], acknowledged),
  "waiting",
  "waiting outranks done in the aggregate attention level",
);
assert.deepEqual(
  attentionCandidates([waiting, done, working], acknowledged).map(
    (candidate) => candidate.paneId,
  ),
  ["%waiting", "%done"],
  "attention jumps contain only active waiting/done notifications",
);

const waitingAcked = acknowledgedPaneIds([waiting, done], {
  "%waiting": waiting.statusTs,
});
assert.ok(waitingAcked.has("%waiting"));
assert.equal(
  waiting.status,
  "waiting",
  "acknowledging does not rewrite the live waiting status",
);
assert.equal(
  attentionLevel([waiting, done], waitingAcked),
  "done",
  "acknowledging waiting leaves the active done notification",
);

const laterWaiting = agent("%waiting", "waiting", 400);
const laterAcked = acknowledgedPaneIds([laterWaiting], {
  "%waiting": waiting.statusTs,
});
assert.equal(
  attentionLevel([laterWaiting], laterAcked),
  "waiting",
  "a later waiting transition reactivates after acknowledgement",
);

const workingAcked = acknowledgedPaneIds([working], {
  "%waiting": waiting.statusTs,
});
assert.equal(
  workingAcked.size,
  0,
  "working has no notification, even when an old acknowledgement remains",
);
assert.equal(
  attentionLevel([working], workingAcked),
  "none",
  "returning to working clears stale attention immediately",
);
assert.deepEqual(
  attentionCandidates([working], workingAcked),
  [],
  "a working agent is not an attention jump target",
);

mkdirSync(join(XDG_STATE, "dotfiles/rail"), { recursive: true });
publishAttention([waiting, done], acknowledged);
assert.equal(readFileSync(ATTENTION_FILE, "utf8"), "waiting");
assert.deepEqual(
  (JSON.parse(readFileSync(ATTENTION_TARGETS_FILE, "utf8")) as Agent[]).map(
    (target) => target.paneId,
  ),
  ["%done", "%waiting"],
  "Sketchybar's target file contains only active notifications",
);

publishAttention([waiting, done], waitingAcked);
assert.equal(
  readFileSync(ATTENTION_FILE, "utf8"),
  "done",
  "acknowledgement lowers the aggregate to the remaining notification",
);
assert.deepEqual(
  (JSON.parse(readFileSync(ATTENTION_TARGETS_FILE, "utf8")) as Agent[]).map(
    (target) => target.paneId,
  ),
  ["%done"],
  "acknowledgement removes the pane from jump targets",
);

publishAttention([working], workingAcked);
assert.equal(
  readFileSync(ATTENTION_FILE, "utf8"),
  "none",
  "the aggregate Sketchybar state clears when the live agent works",
);
assert.deepEqual(
  JSON.parse(readFileSync(ATTENTION_TARGETS_FILE, "utf8")),
  [],
  "the published attention target set clears with the notification",
);

console.log("notification state checks passed");
