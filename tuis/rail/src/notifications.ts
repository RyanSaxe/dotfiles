// Agent attention pushed beyond the terminal: the Sketchybar code-workspace
// highlight and an ntfy phone ping. Both consume current agent status.

import { writeFileSync } from "node:fs";
import { platform } from "node:os";
import { join } from "node:path";

import { run, type Agent, type AgentStatus } from "./data.js";
import { ntfyEndpoint, sendNtfy } from "./attention/ntfy.js";
import type { AttentionItem } from "./attention/types.js";
import { logLine } from "./log.js";
import { XDG_STATE } from "./paths.js";

export const ATTENTION_FILE = join(XDG_STATE, "dotfiles/rail/attention");
export const ATTENTION_TARGETS_FILE = join(
  XDG_STATE,
  "dotfiles/rail/attention-pending.json",
);
const REVIEW_ATTENTION_FILE = join(XDG_STATE, "dotfiles/rail/review-attention");

// waiting outranks done — the same urgency order the rail's rows use.
export type AttentionLevel = "waiting" | "done" | "none";

export function agentIdentity(agent: Agent): string {
  const kind = agent.agentKind || "agent";
  const title = agent.title
    ? ` title=${JSON.stringify(agent.title.replace(/\s+/g, " "))}`
    : "";
  return `${kind} ${agent.session}/${agent.windowName} pane=${agent.paneId}${title}`;
}

export function attentionLevel(
  agents: Agent[],
  acked: Set<string>,
): AttentionLevel {
  const pending = agents.filter(
    (agent) => agent.status !== "working" && !acked.has(agent.paneId),
  );
  if (pending.some((agent) => agent.status === "waiting")) return "waiting";
  if (pending.some((agent) => agent.status === "done")) return "done";
  return "none";
}

let publishedLevel: AttentionLevel | null = null;
let publishedTargets: string | null = null;
let triggerPending = false;
let triggerInFlight = false;

// Visit-clears carries through: acks feed the level, so landing on an
// agent's window dims the sketchybar highlight the same tick it dims the
// rail row.
export function publishAttention(agents: Agent[], acked: Set<string>): void {
  const level = attentionLevel(agents, acked);
  const pending = agents
    .filter((agent) => agent.status !== "working" && !acked.has(agent.paneId))
    .sort(
      (a, b) => b.statusTs - a.statusTs || a.paneId.localeCompare(b.paneId),
    );
  const serializedTargets = JSON.stringify(pending);
  const targetKey = JSON.stringify(
    pending.map((agent) => [
      agent.paneId,
      agent.status,
      agent.statusTs,
      agent.agentKind,
      agent.session,
      agent.windowName,
      agent.title,
    ]),
  );
  const targetsChanged = targetKey !== publishedTargets;
  if (targetsChanged) {
    writeFileSync(ATTENTION_TARGETS_FILE, serializedTargets);
    publishedTargets = targetKey;
  }
  if (!targetsChanged && level === publishedLevel && !triggerPending) return;
  const levelChanged = level !== publishedLevel;
  if (levelChanged) {
    writeFileSync(ATTENTION_FILE, level);
    publishedLevel = level;
  }
  // The level file and Sketchybar event stay edge-triggered. The log records
  // changes to the active set, so two agents at the same level remain
  // distinguishable. Include the kind and pane id so a Claude pane cannot
  // look like a missing Codex pane, and two panes in one window cannot
  // collapse into one label.
  logLine(
    `attention ${level} (pending: ${pending.map(agentIdentity).join(", ") || "none"})`,
  );
  // No sketchybar (Linux, or it isn't running) is fine — the file alone
  // keeps the state truthful for whoever reads it next. On macOS it is not
  // fine, and used to be silent: a failed trigger looked exactly like a
  // successful one, forever.
  if (levelChanged || targetsChanged) triggerPending = true;
  if (triggerPending && !triggerInFlight) {
    triggerInFlight = true;
    run("sketchybar", ["--trigger", "agent_attention_change"])
      .then(() => {
        triggerPending = false;
        triggerInFlight = false;
      })
      .catch((error: unknown) => {
        triggerInFlight = false;
        if (platform() === "darwin") {
          logLine(`sketchybar trigger failed: ${String(error)}`);
        }
      });
  }
}

// The review letter in the menu bar, published the same way the agent one
// is: a file with the level, and an edge-triggered sketchybar event. The bar
// must not read the observer's state itself — that is a JSON document behind
// a lock, and a menu bar polling it every few seconds is how a status
// indicator becomes a source of load.
export type ReviewLevel = "ci" | "review" | "none";

export function reviewLevel(items: readonly AttentionItem[]): ReviewLevel {
  if (items.length === 0) return "none";
  // CI failure outranks comments, matching the rows' own urgency.
  return items.some((item) =>
    item.reasons.some((reason) => reason.kind === "ci"),
  )
    ? "ci"
    : "review";
}

let publishedReviewLevel: ReviewLevel | null = null;

export function publishReviewAttention(items: readonly AttentionItem[]): void {
  const level = reviewLevel(items);
  if (level === publishedReviewLevel) return;
  publishedReviewLevel = level;
  writeFileSync(REVIEW_ATTENTION_FILE, level);
  logLine(`review attention ${level} (${items.length} unacknowledged)`);
  run("sketchybar", ["--trigger", "review_attention_change"]).catch(
    (error: unknown) => {
      if (platform() === "darwin") {
        logLine(`sketchybar trigger failed: ${String(error)}`);
      }
    },
  );
}

const lastStatus = new Map<string, { status: AgentStatus; statusTs: number }>();
let seeded = false;
let wasPresent: boolean | null = null;
let warnedNoChannel = false;

// What rides this tick's ping. Present ticks send nothing. The departure
// tick sweeps in every active waiting/done notification alongside the raw
// transitions, so an agent that finished just before the walk-away is not
// missed.
export function phoneBatch(
  transitions: Agent[],
  agents: Agent[],
  acked: Set<string>,
  present: boolean,
  departed: boolean,
): Agent[] {
  if (present) return [];
  const batch = new Map<string, Agent>();
  for (const agent of transitions) {
    if (agent.status !== "working" && !acked.has(agent.paneId)) {
      batch.set(agent.paneId, agent);
    }
  }
  if (departed) {
    for (const agent of agents) {
      if (agent.status === "working" || acked.has(agent.paneId)) continue;
      batch.set(agent.paneId, agent);
    }
  }
  return [...batch.values()];
}

// One ping per transition into done/waiting, batched per tick. The first
// tick only seeds, so a daemon restart never replays pings (nor replays
// the departure sweep). The phone is the AWAY channel: while present, the
// rail and sketchybar own attention, so every ping is suppressed —
// including the focused window's.
export function pushPhone(
  agents: Agent[],
  acked: Set<string>,
  present: boolean,
): void {
  const rawTransitions: Agent[] = [];
  for (const agent of agents) {
    const previous = lastStatus.get(agent.paneId);
    lastStatus.set(agent.paneId, {
      status: agent.status,
      statusTs: agent.statusTs,
    });
    if (
      !seeded ||
      (previous?.status === agent.status &&
        previous.statusTs === agent.statusTs)
    ) {
      continue;
    }
    if (agent.status === "working" || acked.has(agent.paneId)) continue;
    rawTransitions.push(agent);
  }
  seeded = true;

  const alive = new Set(agents.map((agent) => agent.paneId));
  for (const paneId of lastStatus.keys()) {
    if (!alive.has(paneId)) lastStatus.delete(paneId);
  }

  const departed = wasPresent === true && !present;
  wasPresent = present;
  const transitions = phoneBatch(
    rawTransitions,
    agents,
    acked,
    present,
    departed,
  );

  if (transitions.length === 0) return;
  // A channel that was never configured is the likeliest reason the phone
  // stays quiet, and it used to be indistinguishable from a working one.
  const endpoint = ntfyEndpoint();
  if (endpoint === null) {
    if (!warnedNoChannel) {
      warnedNoChannel = true;
      logLine(
        "no phone channel: set AGENT_NOTIFICATION_ID (or AI_HARNESS_NTFY_URL) in the dotfiles .env",
      );
    }
    return;
  }
  const waiting = transitions.filter((agent) => agent.status === "waiting");
  const first = transitions[0]!;
  const title =
    transitions.length === 1
      ? `Agent ${first.status}: ${first.session}`
      : `${transitions.length} agents need you`;
  const body = transitions
    .map((agent) => `${agentIdentity(agent)}: ${agent.status}`)
    .join("\n");
  // A dropped ping is a missed agent: log it (no retries — an unreliable
  // channel that says so beats retry machinery).
  const names = transitions.map(agentIdentity).join(", ");
  sendNtfy(
    {
      title,
      body,
      priority: waiting.length > 0 ? "high" : "default",
      tags: ["robot"],
    },
    endpoint,
  ).catch((error: unknown) => {
    // Node reports every network failure as "TypeError: fetch failed";
    // the cause is the part that names what actually broke.
    const cause = error instanceof Error ? error.cause : null;
    const detail = cause ? `${String(error)}: ${String(cause)}` : String(error);
    logLine(`ntfy send failed for ${names}: ${detail}`);
  });
}
