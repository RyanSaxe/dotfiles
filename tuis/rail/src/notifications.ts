// Agent attention pushed beyond the terminal: the sketchybar code-workspace
// highlight and an ntfy phone ping. Both are edge-triggered on status
// transitions — never levels — so nothing repeats while a state persists.

import { writeFileSync } from "node:fs";
import { platform } from "node:os";
import { join } from "node:path";

import { run, type Agent, type AgentStatus } from "./data.js";
import { ntfyEndpoint, sendNtfy } from "./attention/ntfy.js";
import { logLine } from "./log.js";
import { XDG_STATE } from "./paths.js";

const ATTENTION_FILE = join(XDG_STATE, "dotfiles/rail/attention");

// waiting outranks done — the same urgency order the rail's rows use.
export type AttentionLevel = "waiting" | "done" | "none";

export function attentionLevel(
  agents: Agent[],
  acked: Set<string>,
): AttentionLevel {
  const pending = agents.filter((agent) => !acked.has(agent.paneId));
  if (pending.some((agent) => agent.status === "waiting")) return "waiting";
  if (pending.some((agent) => agent.status === "done")) return "done";
  return "none";
}

let publishedLevel: AttentionLevel | null = null;

// Visit-clears carries through: acks feed the level, so landing on an
// agent's window dims the sketchybar highlight the same tick it dims the
// rail row.
export function publishAttention(agents: Agent[], acked: Set<string>): void {
  const level = attentionLevel(agents, acked);
  if (level === publishedLevel) return;
  publishedLevel = level;
  writeFileSync(ATTENTION_FILE, level);
  // Edge-triggered, so this is one line per level change — the only record
  // of why the bar looks the way it does. Without it, diagnosing a quiet
  // notification means reconstructing the ack store by hand.
  const pending = agents
    .filter((agent) => agent.status !== "working" && !acked.has(agent.paneId))
    .map((agent) => `${agent.session}/${agent.windowName}`);
  logLine(`attention ${level} (pending: ${pending.join(", ") || "none"})`);
  // No sketchybar (Linux, or it isn't running) is fine — the file alone
  // keeps the state truthful for whoever reads it next. On macOS it is not
  // fine, and used to be silent: a failed trigger looked exactly like a
  // successful one, forever.
  run("sketchybar", ["--trigger", "agent_attention_change"]).catch(
    (error: unknown) => {
      if (platform() === "darwin") {
        logLine(`sketchybar trigger failed: ${String(error)}`);
      }
    },
  );
}

const lastStatus = new Map<string, AgentStatus>();
let seeded = false;
let wasPresent: boolean | null = null;
let warnedNoChannel = false;

// What rides this tick's ping. Present ticks send nothing. The departure
// tick sweeps in every un-acked done/waiting agent alongside the raw
// transitions — an agent that finished just before the walk-away is
// unacked, so leaving is pure latency, never a miss window.
export function phoneBatch(
  transitions: Agent[],
  agents: Agent[],
  acked: Set<string>,
  present: boolean,
  departed: boolean,
): Agent[] {
  if (present) return [];
  const batch = new Map<string, Agent>();
  for (const agent of transitions) batch.set(agent.paneId, agent);
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
    lastStatus.set(agent.paneId, agent.status);
    if (!seeded || previous === agent.status) continue;
    if (agent.status === "working") continue;
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
    .map((agent) => `${agent.session}/${agent.windowName}: ${agent.status}`)
    .join("\n");
  // A dropped ping is a missed agent: log it (no retries — an unreliable
  // channel that says so beats retry machinery).
  const names = transitions
    .map((agent) => `${agent.session}/${agent.windowName}`)
    .join(", ");
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
