import { blank, line } from "../cells.js";
import type { Agent, Window } from "../data.js";
import { railBg, type Palette } from "../theme.js";
import { elapsedSpan, pill, stateColor, type RailRow } from "./rows.js";

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
      .find((candidate) => candidate !== undefined);
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
        agent ? elapsedSpan(agent.elapsedSecs, palette) : undefined,
      ),
      item: true,
    });
  }
  return rows;
}
