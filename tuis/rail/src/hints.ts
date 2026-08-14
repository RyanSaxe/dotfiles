// Jump hints: every agent gets a letter; alt+; enters a one-key tmux table
// where that letter jumps straight to the agent's pane. The daemon assigns
// letters (preferring the session's first letter so they stay guessable)
// and writes the mapping file `rail jump` reads.

import { mkdirSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";

import type { Agent } from "./data.js";

const HINTS_PATH = join(
  process.env.XDG_STATE_HOME ?? join(homedir(), ".local/state"),
  "dotfiles/rail/hints.tsv",
);

// Home row first, then the rest of the alphabet.
const POOL = "asdfghjklqwertyuiopzxcvbnm";

export function assignHints(agents: Agent[]): Map<string, string> {
  const hints = new Map<string, string>();
  const taken = new Set<string>();
  // Deterministic order: assignments only reshuffle when agents come or go.
  const ordered = [...agents].sort((a, b) => a.paneId.localeCompare(b.paneId));
  for (const agent of ordered) {
    const preferred = (agent.session[0] ?? "").toLowerCase();
    let letter = "";
    if (preferred && POOL.includes(preferred) && !taken.has(preferred)) {
      letter = preferred;
    } else {
      letter = [...POOL].find((candidate) => !taken.has(candidate)) ?? "";
    }
    if (!letter) break;
    taken.add(letter);
    hints.set(agent.paneId, letter);
  }
  return hints;
}

let lastWritten = "";

export function writeHints(agents: Agent[], hints: Map<string, string>): void {
  const lines = agents
    .filter((agent) => hints.has(agent.paneId))
    .map(
      (agent) =>
        `${hints.get(agent.paneId)}\t${agent.session}\t${agent.paneId}`,
    )
    .sort()
    .join("\n");
  if (lines === lastWritten) return;
  lastWritten = lines;
  mkdirSync(dirname(HINTS_PATH), { recursive: true });
  writeFileSync(HINTS_PATH, lines + (lines ? "\n" : ""));
}
