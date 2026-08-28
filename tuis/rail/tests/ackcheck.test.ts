// Exercises the visit-clears ack lifecycle and fails loudly on any
// deviation. `npm test` runs every test under a throwaway XDG_STATE_HOME,
// so this never touches the real acks.

import assert from "node:assert/strict";

import { loadAcks, updateAcks } from "../src/acks.js";
import type { Agent, Pane } from "../src/data.js";

const agent = (statusTs: number, updatedTs = statusTs): Agent => ({
  session: "s",
  windowName: "w",
  paneId: "%1",
  status: "done",
  statusTs,
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

const FOCUSED = new Set(["s"]);
const UNFOCUSED = new Set<string>();

const acks = loadAcks();
assert.equal(
  updateAcks(acks, [agent(100)], pane(false, true), FOCUSED).size,
  0,
  "unvisited stays colored",
);
assert.equal(
  updateAcks(acks, [agent(100)], pane(true, true), UNFOCUSED).size,
  0,
  "unfocused terminal does not ack",
);
assert.equal(
  updateAcks(acks, [agent(100)], pane(true, true), new Set(["elsewhere"])).size,
  0,
  "focus on another session does not ack this one",
);
assert.equal(
  updateAcks(acks, [agent(100)], pane(true, true), FOCUSED).size,
  1,
  "visiting acks",
);
assert.equal(
  updateAcks(acks, [agent(100)], pane(false, true), FOCUSED).size,
  1,
  "ack persists after leaving",
);
assert.equal(
  updateAcks(acks, [agent(200)], pane(false, true), FOCUSED).size,
  0,
  "new status re-fires",
);
assert.equal(
  updateAcks(acks, [agent(200)], pane(true, false), FOCUSED).size,
  0,
  "detached visit does not ack",
);
assert.equal(
  updateAcks(acks, [agent(300, 10_000)], pane(true, true), FOCUSED).size,
  1,
  "a visited heartbeat does not change the transition being acknowledged",
);
assert.equal(
  loadAcks()["%1"],
  300,
  "acks persist the status transition timestamp",
);
console.log("ack lifecycle ok");
