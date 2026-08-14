import { blank, fmtElapsed, line, type Span } from "../cells.js";
import type { Agent, Window } from "../data.js";
import type { Palette } from "../theme.js";
import { railBg } from "./header.js";

export function stateColor(status: Agent["status"], palette: Palette): string {
  switch (status) {
    case "working":
      return palette.mauve;
    case "waiting":
      return palette.peach;
    case "done":
      return palette.green;
  }
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
    { text: "", fg: bg, bg: lineBackground },
    { text, fg, bg },
    { text: "", fg: bg, bg: lineBackground },
  ];
}

// A rail row paired with whether it is an item (a window/agent) or
// furniture (spacers, hairlines) — pagination counts items, not rows.
export interface RailRow {
  text: string;
  item: boolean;
}

// Two orthogonal channels, never mixed: the accent-filled pill means only
// "you are here"; a colored title always means agent state. Every row is
// preceded by a blank spacer, so rows breathe and the gap below the header
// rule equals the gap above the next hairline.
export function windowRows(
  windows: Window[],
  agentsByPane: Map<string, Agent>,
  acked: Set<string>,
  palette: Palette,
  width: number,
): RailRow[] {
  const bg = railBg(palette);
  const rows: RailRow[] = [];
  for (const win of windows) {
    const agent = win.paneIds
      .map((paneId) => agentsByPane.get(paneId))
      .find((a) => a !== undefined);
    const marker = win.active
      ? pill(String(win.index), palette.base, palette.accent, bg)
      : pill(String(win.index), palette.dim2, palette.surface0, bg);
    // An acknowledged agent reads like a plain window: the state was seen,
    // the color returns only on a new status event.
    const titleFg =
      agent && !acked.has(agent.paneId)
        ? stateColor(agent.status, palette)
        : win.active
          ? palette.text
          : palette.dim2;
    rows.push({ text: blank(width, bg), item: false });
    rows.push({
      text: line(
        width,
        bg,
        [
          ...marker,
          { text: " ", fg: palette.text },
          { text: win.name, fg: titleFg },
        ],
        agent
          ? { text: fmtElapsed(agent.elapsedSecs), fg: palette.dim }
          : undefined,
      ),
      item: true,
    });
  }
  return rows;
}
