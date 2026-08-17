// Agent attention pushed beyond the terminal: the sketchybar code-workspace
// highlight and an ntfy phone ping. Both are edge-triggered on status
// transitions — never levels — so nothing repeats while a state persists.

import { writeFileSync } from "node:fs";
import { join } from "node:path";

import { run, type Agent, type AgentStatus } from "./data.js";
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
  // No sketchybar (Linux, or it isn't running) is fine — the file alone
  // keeps the state truthful for whoever reads it next.
  run("sketchybar", ["--trigger", "agent_attention_change"]).catch(() => {});
}

const NTFY_URL =
  process.env["AI_HARNESS_NTFY_URL"] ??
  (process.env["CLAUDE_NOTIFICATION_ID"]
    ? `https://ntfy.sh/ai-agent-notification-${process.env["CLAUDE_NOTIFICATION_ID"]}`
    : null);

const lastStatus = new Map<string, AgentStatus>();
let seeded = false;

// One ping per transition into done/waiting, batched per tick. The first
// tick only seeds, so a daemon restart never replays pings. The phone is
// the AWAY channel: while present, the rail and sketchybar own attention,
// so every ping is suppressed — including the focused window's.
export function pushPhone(agents: Agent[], present: boolean): void {
  const transitions: Agent[] = [];
  for (const agent of agents) {
    const previous = lastStatus.get(agent.paneId);
    lastStatus.set(agent.paneId, agent.status);
    if (!seeded || previous === agent.status) continue;
    if (agent.status === "working") continue;
    transitions.push(agent);
  }
  seeded = true;

  const alive = new Set(agents.map((agent) => agent.paneId));
  for (const paneId of lastStatus.keys()) {
    if (!alive.has(paneId)) lastStatus.delete(paneId);
  }

  if (present || transitions.length === 0 || !NTFY_URL) return;
  const waiting = transitions.filter((agent) => agent.status === "waiting");
  const first = transitions[0]!;
  const title =
    transitions.length === 1
      ? `Agent ${first.status}: ${first.session}`
      : `${transitions.length} agents need you`;
  const body = transitions
    .map((agent) => `${agent.session}/${agent.windowName}: ${agent.status}`)
    .join("\n");
  fetch(NTFY_URL, {
    method: "POST",
    headers: {
      Title: title,
      Priority: waiting.length > 0 ? "high" : "default",
      Tags: "robot",
    },
    body,
  }).catch(() => {});
}
