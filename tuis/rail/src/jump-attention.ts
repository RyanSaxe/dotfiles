// Jump to the first live agent in the rail's current unacknowledged set.
// The daemon publishes this set after status stabilization, so the command
// cannot revive Workmux's raw status flicker or choose a different pane than
// the rail is showing.

import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { acknowledgedPaneIds, loadAcks, type AckStore } from "./acks.js";
import { collectAgents, run, tmux, type Agent } from "./data.js";
import { agentIdentity, ATTENTION_TARGETS_FILE } from "./notifications.js";
import { sortByUrgency } from "./sections/rows.js";

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
    return Array.isArray(parsed) ? (parsed as Agent[]) : null;
  } catch {
    return null;
  }
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
  const agents = published ?? (await collectAgents());
  const acks: AckStore = loadAcks();
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
        "quiet",
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
