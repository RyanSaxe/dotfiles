// Shared row vocabulary for the rail's sections: the pill shape, agent
// state colors, urgency ranking, and the elapsed-timer span. Sections
// import from here, never from each other.

import { fmtElapsed, type Span } from "../cells.js";
import type { Agent } from "../data.js";
import { blend, DIM_KEEP, railBg, type Palette } from "../theme.js";

// A rail row paired with whether it is an item (a window/agent) or
// furniture (spacers, hairlines) — pagination counts items, not rows.
export interface RailRow {
  text: string;
  item: boolean;
}

// A three-cell pill: powerline caps around a single character. The SAME
// shape everywhere in the rail — window numbers and elsewhere hints differ
// only in color, never geometry.
export function pill(
  text: string,
  fg: string,
  bg: string,
  lineBackground: string,
): Span[] {
  return [
    { text: "", fg: bg, bg: lineBackground },
    { text, fg, bg },
    { text: "", fg: bg, bg: lineBackground },
  ];
}

export function stateColor(status: Agent["status"], palette: Palette): string {
  switch (status) {
    case "working":
      return palette.statusWorking;
    case "waiting":
      return palette.statusWaiting;
    case "done":
      return palette.statusDone;
  }
}

// Urgency: waiting outranks working outranks done; acked rows rank last —
// their news has been seen.
const URGENCY: Record<Agent["status"], number> = {
  waiting: 0,
  working: 1,
  done: 2,
};

export function agentRank(agent: Agent, acked: Set<string>): number {
  return acked.has(agent.paneId) ? 3 : URGENCY[agent.status];
}

// Timers whisper by default — blended well into the slab so their minute
// ticks never pull the eye. Past eight hours the timer turns red: an agent
// left alone that long IS the thing to look at.
const ELAPSED_ATTENTION_SECS = 8 * 60 * 60;

export function elapsedSpan(secs: number, palette: Palette): Span {
  const fg =
    secs >= ELAPSED_ATTENTION_SECS
      ? palette.red
      : blend(palette.dim, railBg(palette), DIM_KEEP);
  return { text: fmtElapsed(secs), fg };
}
