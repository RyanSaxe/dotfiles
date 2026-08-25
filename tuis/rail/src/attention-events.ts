// Durable attention events. Workmux exposes the agent's current status, but a
// completion is an event that must remain visible until it is acknowledged.
// Keeping the two concepts separate prevents a later working status from
// erasing an unread done/waiting notification.

import { mkdirSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";

import type { AckStore } from "./acks.js";
import type { Agent } from "./data.js";
import { XDG_STATE } from "./paths.js";

export type AttentionEventStatus = "waiting" | "done";

export interface AttentionEvent {
  status: AttentionEventStatus;
  updatedTs: number;
}

export type AttentionEvents = Record<string, AttentionEvent>;

export const ATTENTION_EVENTS_PATH = join(
  XDG_STATE,
  "dotfiles/rail/attention-events.json",
);

export function loadAttentionEvents(): AttentionEvents {
  try {
    return JSON.parse(
      readFileSync(ATTENTION_EVENTS_PATH, "utf8"),
    ) as AttentionEvents;
  } catch {
    return {};
  }
}

export function saveAttentionEvents(events: AttentionEvents): void {
  mkdirSync(dirname(ATTENTION_EVENTS_PATH), { recursive: true });
  const temp = `${ATTENTION_EVENTS_PATH}.${process.pid}.tmp`;
  writeFileSync(temp, JSON.stringify(events));
  renameSync(temp, ATTENTION_EVENTS_PATH);
}

function acknowledged(
  event: AttentionEvent,
  acks: AckStore,
  paneId: string,
): boolean {
  return (acks[paneId] ?? 0) >= event.updatedTs;
}

// Record only stabilized waiting/done statuses. A later working status does
// not erase an unread event; visiting the pane or deleting it does.
export function reconcileAttentionEvents(
  events: AttentionEvents,
  agents: Agent[],
  acks: AckStore,
  rawAgents: Agent[] = agents,
): boolean {
  let changed = false;
  const live = new Set(agents.map((agent) => agent.paneId));
  const rawByPane = new Map(rawAgents.map((agent) => [agent.paneId, agent]));

  for (const paneId of Object.keys(events)) {
    if (!live.has(paneId)) {
      delete events[paneId];
      changed = true;
    }
  }

  for (const agent of agents) {
    let current = events[agent.paneId];
    if (current !== undefined && acknowledged(current, acks, agent.paneId)) {
      delete events[agent.paneId];
      changed = true;
      current = undefined;
    }
    const raw = rawByPane.get(agent.paneId);
    const candidates: AttentionEvent[] = [];
    if (agent.status !== "working") {
      candidates.push({ status: agent.status, updatedTs: agent.updatedTs });
    }
    // A done hook is a meaningful completion event even when the agent is
    // prompted again before the 30-second stabilization window expires.
    // Waiting remains stabilization-gated because permission/status prompts
    // are the noisy state this window is meant to suppress.
    if (raw?.status === "done") {
      candidates.push({ status: "done", updatedTs: raw.updatedTs });
    }
    if (candidates.length === 0) continue;
    const next = candidates.reduce((latest, candidate) =>
      candidate.updatedTs >= latest.updatedTs ? candidate : latest,
    );
    if ((acks[agent.paneId] ?? 0) >= next.updatedTs) continue;
    if (
      current === undefined ||
      next.updatedTs > current.updatedTs ||
      (next.updatedTs === current.updatedTs && next.status !== current.status)
    ) {
      events[agent.paneId] = {
        status: next.status,
        updatedTs: next.updatedTs,
      };
      changed = true;
    }
  }

  return changed;
}

// Surface an unread event through the existing Agent vocabulary. The live
// agent remains the source for pane/session/title identity; only its displayed
// attention status is overlaid while the event is pending.
export function surfaceAttentionEvents(
  agents: Agent[],
  events: AttentionEvents,
  acks: AckStore,
): Agent[] {
  return agents.map((agent) => {
    const event = events[agent.paneId];
    if (
      event === undefined ||
      agent.status !== "working" ||
      acknowledged(event, acks, agent.paneId)
    ) {
      return agent;
    }
    return {
      ...agent,
      status: event.status,
      updatedTs: event.updatedTs,
    };
  });
}
