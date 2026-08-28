// Jump to the first live agent in the rail's current active-notification set.
// The daemon publishes this set after status stabilization, so the command
// does not revive Workmux's raw status flicker or overlay a notification onto
// a working agent.

import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { acknowledgedPaneIds, loadAcks, type AckStore } from "./acks.js";
import {
  collectAgents,
  run,
  stabilizeAgents,
  tmux,
  type Agent,
} from "./data.js";
import { agentIdentity, ATTENTION_TARGETS_FILE } from "./notifications.js";
import { sortByUrgency } from "./sections/rows.js";
import { loadStableStatuses } from "./stability.js";

const GOTO_PANE = join(homedir(), ".config/tmux/scripts/goto-pane.sh");

export function attentionCandidates(
  agents: Agent[],
  acked: Set<string>,
): Agent[] {
  return sortByUrgency(
    agents.filter(
      (agent) => agent.status !== "working" && !acked.has(agent.paneId),
    ),
    acked,
  );
}

function readPublishedAgents(): Agent[] | null {
  try {
    const parsed = JSON.parse(
      readFileSync(ATTENTION_TARGETS_FILE, "utf8"),
    ) as unknown;
    if (!Array.isArray(parsed)) return null;
    return parsed.filter(isPublishedAgent);
  } catch {
    return null;
  }
}

function isPublishedAgent(value: unknown): value is Agent {
  if (typeof value !== "object" || value === null) return false;
  const agent = value as Partial<Agent>;
  return (
    typeof agent.session === "string" &&
    typeof agent.windowName === "string" &&
    typeof agent.paneId === "string" &&
    (agent.status === "waiting" || agent.status === "done") &&
    typeof agent.statusTs === "number" &&
    Number.isFinite(agent.statusTs)
  );
}

async function livePane(paneId: string): Promise<boolean> {
  try {
    const { stdout } = await tmux(
      "display-message",
      "-p",
      "-t",
      paneId,
      "#{pane_id}",
    );
    return stdout.trim() === paneId;
  } catch {
    return false;
  }
}

export async function jumpAttention(): Promise<Agent | null> {
  const published = readPublishedAgents();
  const acks: AckStore = loadAcks();
  let live: Agent[] | null = null;
  try {
    live = await collectAgents();
  } catch {
    // The last published target set is safer than failing a jump during a
    // transient Workmux read failure.
  }
  const current =
    live === null
      ? published
      : (() => {
          const settled = stabilizeAgents(
            live,
            loadStableStatuses(),
            Date.now() / 1000,
          );
          if (published === null) return settled;
          const settledByPane = new Map(
            settled.map((agent) => [agent.paneId, agent]),
          );
          return published.flatMap((target) => {
            const liveAgent = settledByPane.get(target.paneId);
            return liveAgent?.status === target.status &&
              liveAgent.statusTs === target.statusTs
              ? [liveAgent]
              : [];
          });
        })();
  const agents = current ?? [];
  const acked = acknowledgedPaneIds(agents, acks);

  for (const agent of attentionCandidates(agents, acked)) {
    // Workmux can publish a state transition just before the pane/window is
    // removed. Re-check the pane at the last responsible moment and let the
    // next candidate win if it disappeared.
    if (!(await livePane(agent.paneId))) continue;
    try {
      await run(GOTO_PANE, [
        agent.session,
        agent.paneId,
        agent.paneId,
        "strict",
      ]);
      console.log(`rail: jumped to ${agentIdentity(agent)}`);
      return agent;
    } catch {
      // A pane can disappear after the validation and before goto-pane's
      // own validation. Continue with the same live snapshot rather than
      // jumping to an unrelated pane.
    }
  }

  console.log("rail: no live unacknowledged agent attention");
  return null;
}

if (
  process.argv[1] !== undefined &&
  resolve(process.argv[1]) === fileURLToPath(import.meta.url)
) {
  jumpAttention().catch((error: unknown) => {
    console.error(`rail: attention jump failed: ${String(error)}`);
    process.exitCode = 1;
  });
}
