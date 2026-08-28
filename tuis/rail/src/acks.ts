// Visit-clears acknowledgement. Landing on an agent's window clears the
// current waiting/done notification everywhere, persistently. Acks are keyed
// by pane id and store the last acknowledged status transition timestamp.

import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";

import { XDG_STATE } from "./paths.js";
import type { Agent, Pane } from "./data.js";

const ACKS_PATH = join(XDG_STATE, "dotfiles/rail/acks.json");
const UNACKNOWLEDGED = -1;

export type AckStore = Record<string, number>;

export function loadAcks(): AckStore {
  try {
    return JSON.parse(readFileSync(ACKS_PATH, "utf8")) as AckStore;
  } catch {
    return {};
  }
}

// Resolve the persisted transition timestamps against the current live
// snapshot. A working agent has no notification to acknowledge, even if an
// old record remains for its pane.
export function acknowledgedPaneIds(
  agents: Agent[],
  acks: AckStore,
): Set<string> {
  return new Set(
    agents
      .filter(
        (agent) =>
          agent.status !== "working" &&
          (acks[agent.paneId] ?? UNACKNOWLEDGED) >= agent.statusTs,
      )
      .map((agent) => agent.paneId),
  );
}

// A pane is "visited" when its window is the active window of a session
// someone is attached to AND that session's terminal window owns OS focus.
// An attached client sitting behind a browser acks nothing.
function visitedPaneIds(
  agents: Agent[],
  panes: Pane[],
  focusedSessions: Set<string>,
): Set<string> {
  const visible = new Set<string>();
  const attachedActive = new Set<string>();
  for (const pane of panes) {
    if (
      pane.windowActive &&
      pane.sessionAttached &&
      focusedSessions.has(pane.session)
    ) {
      attachedActive.add(pane.paneId);
    }
  }
  for (const agent of agents) {
    if (attachedActive.has(agent.paneId)) visible.add(agent.paneId);
  }
  return visible;
}

// Advance acks for visited waiting/done agents, prune panes that no longer
// exist, and persist when anything moved. Working is never acknowledged: it
// is live information, not a notification.
export function updateAcks(
  acks: AckStore,
  agents: Agent[],
  panes: Pane[],
  focusedSessions: Set<string>,
): Set<string> {
  let changed = false;
  const visited = visitedPaneIds(agents, panes, focusedSessions);
  const live = new Set(agents.map((agent) => agent.paneId));

  for (const paneId of Object.keys(acks)) {
    if (!live.has(paneId)) {
      delete acks[paneId];
      changed = true;
    }
  }
  for (const agent of agents) {
    if (
      agent.status !== "working" &&
      visited.has(agent.paneId) &&
      (acks[agent.paneId] ?? UNACKNOWLEDGED) < agent.statusTs
    ) {
      acks[agent.paneId] = agent.statusTs;
      changed = true;
    }
  }
  if (changed) {
    mkdirSync(dirname(ACKS_PATH), { recursive: true });
    writeFileSync(ACKS_PATH, JSON.stringify(acks));
  }
  return acknowledgedPaneIds(agents, acks);
}
