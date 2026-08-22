// Jump hints: the elsewhere section's rows are numbered by display
// position — 1 is always the top row of the rail you are looking at.
// alt+space enters a one-key tmux table where the digit jumps to that row.
// The legacy `a`/Enter global jump remains available to scripts, but it is
// no longer a user-facing key-table action. It targets the globally
// most-urgent agent, CURRENT SESSION INCLUDED — digits cover what the
// elsewhere list shows and `a` covers everything. Because
// "elsewhere" is relative to the viewing session, assignments are per
// session; the daemon writes one mapping line per (viewing session, key).

import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";

import { XDG_STATE } from "./paths.js";
import { sortByUrgency } from "./sections/rows.js";
import type { Agent } from "./data.js";

const HINTS_PATH = join(XDG_STATE, "dotfiles/rail/hints.tsv");

// Digits only: past nine agents the dashboard is the overflow surface.
const MAX_HINTS = 9;

// One digit map per viewing session, numbering that session's elsewhere
// rows in their exact display order.
export function assignHints(
  agents: Agent[],
  sessions: Iterable<string>,
  acked: Set<string>,
): Map<string, Map<string, string>> {
  const bySession = new Map<string, Map<string, string>>();
  for (const session of sessions) {
    const elsewhere = sortByUrgency(
      agents.filter((agent) => agent.session !== session),
      acked,
    );
    const hints = new Map<string, string>();
    for (const [index, agent] of elsewhere.slice(0, MAX_HINTS).entries()) {
      hints.set(agent.paneId, String(index + 1));
    }
    bySession.set(session, hints);
  }
  return bySession;
}

let lastWritten = "";

// Line format: viewing session \t key \t target session \t pane id,
// where key is a digit or the literal `a` (global most-urgent). `rail
// jump` resolves the caller's session to a key.
export function writeHints(
  agents: Agent[],
  bySession: Map<string, Map<string, string>>,
  acked: Set<string>,
): void {
  const sessionOf = new Map(agents.map((agent) => [agent.paneId, agent]));
  const top = sortByUrgency(agents, acked)[0];
  const lines: string[] = [];
  for (const [session, hints] of bySession) {
    for (const [paneId, digit] of hints) {
      const target = sessionOf.get(paneId);
      if (target)
        lines.push(`${session}\t${digit}\t${target.session}\t${paneId}`);
    }
    if (top) lines.push(`${session}\ta\t${top.session}\t${top.paneId}`);
  }
  const joined = lines.sort().join("\n");
  if (joined === lastWritten) return;
  lastWritten = joined;
  mkdirSync(dirname(HINTS_PATH), { recursive: true });
  writeFileSync(HINTS_PATH, joined + (joined ? "\n" : ""));
}
