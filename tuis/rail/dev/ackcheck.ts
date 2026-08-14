// Exercises the visit-clears ack lifecycle against an isolated state dir
// (set XDG_STATE_HOME before running) and fails loudly on any deviation.
//
//   XDG_STATE_HOME=$(mktemp -d) npx tsx dev/ackcheck.ts

import assert from "node:assert/strict";

import { loadAcks, updateAcks } from "../src/acks.js";
import type { Agent, Pane } from "../src/data.js";

const agent = (updatedTs: number): Agent => ({
  session: "s",
  windowName: "w",
  paneId: "%1",
  status: "done",
  title: "t",
  elapsedSecs: 5,
  updatedTs,
  worktree: "s",
  branch: "main",
});

const pane = (windowActive: boolean, sessionAttached: boolean): Pane[] => [
  {
    session: "s",
    sessionAttached,
    windowId: "@1",
    windowIndex: 1,
    windowName: "w",
    windowActive,
    windowPanes: 2,
    windowWidth: 200,
    paneId: "%1",
    paneActive: false,
    tty: "/dev/null",
    width: 34,
    height: 40,
    isRail: false,
    historySize: 0,
    inMode: false,
  },
];

const acks = loadAcks();
assert.equal(
  updateAcks(acks, [agent(100)], pane(false, true)).size,
  0,
  "unvisited stays colored",
);
assert.equal(
  updateAcks(acks, [agent(100)], pane(true, true)).size,
  1,
  "visiting acks",
);
assert.equal(
  updateAcks(acks, [agent(100)], pane(false, true)).size,
  1,
  "ack persists after leaving",
);
assert.equal(
  updateAcks(acks, [agent(200)], pane(false, true)).size,
  0,
  "new status re-fires",
);
assert.equal(
  updateAcks(acks, [agent(200)], pane(true, false)).size,
  0,
  "detached visit does not ack",
);
assert.equal(loadAcks()["%1"], 100, "acks persist to disk");
console.log("ack lifecycle ok");
