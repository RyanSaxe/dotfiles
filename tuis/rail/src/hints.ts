// Jump hints: the elsewhere section's rows are numbered by display
// position — 1 is always the top row of the rail you are looking at.
// alt+a enters a one-key tmux table where the digit jumps to that row
// (a / Enter jump to row 1, "what needs me most"). Because "elsewhere"
// is relative to the viewing session, assignments are per session; the
// daemon writes one mapping line per (viewing session, digit).

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

// Line format: viewing session \t digit \t target session \t pane id.
// `rail jump` greps the caller's session to resolve a digit.
export function writeHints(
  agents: Agent[],
  bySession: Map<string, Map<string, string>>,
): void {
  const sessionOf = new Map(agents.map((agent) => [agent.paneId, agent]));
  const lines: string[] = [];
  for (const [session, hints] of bySession) {
    for (const [paneId, digit] of hints) {
      const target = sessionOf.get(paneId);
      if (target)
        lines.push(`${session}\t${digit}\t${target.session}\t${paneId}`);
    }
  }
  const joined = lines.sort().join("\n");
  if (joined === lastWritten) return;
  lastWritten = joined;
  mkdirSync(dirname(HINTS_PATH), { recursive: true });
  writeFileSync(HINTS_PATH, joined + (joined ? "\n" : ""));
}
