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
// only in color, never geometry. The caps are Private Use Area glyphs
// (nerd-font rounded halves), written as escapes because editors and
// review tools render them invisibly.
export function pill(
  text: string,
  fg: string,
  bg: string,
  lineBackground: string,
): Span[] {
  return [
    { text: "\ue0b6", fg: bg, bg: lineBackground },
    { text, fg, bg },
    { text: "\ue0b4", fg: bg, bg: lineBackground },
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

// Timers whisper — blended well into the slab so their minute ticks never
// pull the eye — but in the agent's STATE hue, so a truncated title still
// shows its color through the timer. Acked rows drop to the neutral dim.
// Past eight hours the timer turns full red: an agent left alone that
// long IS the thing to look at.
const ELAPSED_ATTENTION_SECS = 8 * 60 * 60;

export function elapsedSpan(
  agent: Agent,
  acked: Set<string>,
  palette: Palette,
): Span {
  const secs = agent.elapsedSecs;
  if (secs >= ELAPSED_ATTENTION_SECS) {
    return { text: fmtElapsed(secs), fg: palette.red };
  }
  const hue = acked.has(agent.paneId)
    ? palette.dim
    : stateColor(agent.status, palette);
  return { text: fmtElapsed(secs), fg: blend(hue, railBg(palette), DIM_KEEP) };
}
