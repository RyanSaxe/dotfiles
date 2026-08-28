import assert from "node:assert/strict";

import { acknowledgedPaneIds } from "../src/acks.js";
import { attentionCandidates } from "../src/jump-attention.js";
import type { Agent } from "../src/data.js";
import { agentIdentity } from "../src/notifications.js";

const agent = (
  paneId: string,
  status: Agent["status"],
  updatedTs: number,
): Agent => ({
  session: "dotfiles",
  windowName: paneId,
  paneId,
  agentKind: paneId === "%claude" ? "claude" : "codex",
  status,
  statusTs: updatedTs,
  title: paneId,
  elapsedSecs: 0,
  updatedTs,
  worktree: "dotfiles",
  branch: "develop",
});

const waitingOld = agent("%waiting-old", "waiting", 100);
const waitingNew = agent("%waiting-new", "waiting", 200);
const done = agent("%done", "done", 300);
const working = agent("%working", "working", 400);

assert.match(
  agentIdentity(agent("%claude", "done", 500)),
  /^claude dotfiles\/%claude pane=%claude title=/,
  "attention targets name the agent kind and pane",
);

assert.deepEqual(
  attentionCandidates(
    [done, working, waitingOld, waitingNew],
    new Set<string>(),
  ).map((candidate) => candidate.paneId),
  ["%waiting-new", "%waiting-old", "%done"],
  "jump attention follows rail urgency and excludes working agents",
);

assert.deepEqual(
  attentionCandidates(
    [waitingOld, waitingNew, done],
    new Set(["%waiting-new"]),
  ).map((candidate) => candidate.paneId),
  ["%waiting-old", "%done"],
  "jump attention skips panes already acknowledged by the rail",
);

assert.deepEqual(
  [
    ...acknowledgedPaneIds([waitingNew, done], {
      "%waiting-new": 199,
      "%done": 300,
    }),
  ],
  ["%done"],
  "an ack only covers the status timestamp it actually visited",
);

console.log("attention jump checks passed");
