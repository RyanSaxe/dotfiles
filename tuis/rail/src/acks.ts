// Visit-clears acknowledgement. Landing on an agent's window clears its
// done/waiting color everywhere, persistently — the color returns only
// when a NEW status event arrives. Acks are keyed by pane id and store the
// acknowledged status timestamp; "new" means updatedTs > acked ts.

import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";

import { XDG_STATE } from "./paths.js";
import type { Agent, Pane } from "./data.js";

const ACKS_PATH = join(XDG_STATE, "dotfiles/rail/acks.json");

export type AckStore = Record<string, number>;

export function loadAcks(): AckStore {
  try {
    return JSON.parse(readFileSync(ACKS_PATH, "utf8")) as AckStore;
  } catch {
    return {};
  }
}

// A pane is "visited" when its window is the active window of a session
// someone is actually attached to — that is the moment a human saw it.
function visitedPaneIds(agents: Agent[], panes: Pane[]): Set<string> {
  const visible = new Set<string>();
  const attachedActive = new Set<string>();
  for (const pane of panes) {
    if (pane.windowActive && pane.sessionAttached) {
      attachedActive.add(pane.paneId);
    }
  }
  for (const agent of agents) {
    if (attachedActive.has(agent.paneId)) visible.add(agent.paneId);
  }
  return visible;
}

// Advance acks for visited agents, prune agents that no longer exist, and
// persist when anything moved. Returns the set of pane ids whose current
// status is acknowledged (working is never acked — it is information, not
// a notification).
export function updateAcks(
  acks: AckStore,
  agents: Agent[],
  panes: Pane[],
): Set<string> {
  let changed = false;
  const visited = visitedPaneIds(agents, panes);
  const live = new Set(agents.map((agent) => agent.paneId));

  for (const paneId of Object.keys(acks)) {
    if (!live.has(paneId)) {
      delete acks[paneId];
      changed = true;
    }
  }
  const acked = new Set<string>();
  for (const agent of agents) {
    if (
      visited.has(agent.paneId) &&
      (acks[agent.paneId] ?? 0) < agent.updatedTs
    ) {
      acks[agent.paneId] = agent.updatedTs;
      changed = true;
    }
    if (
      agent.status !== "working" &&
      (acks[agent.paneId] ?? 0) >= agent.updatedTs
    ) {
      acked.add(agent.paneId);
    }
  }
  if (changed) {
    mkdirSync(dirname(ACKS_PATH), { recursive: true });
    writeFileSync(ACKS_PATH, JSON.stringify(acks));
  }
  return acked;
}
