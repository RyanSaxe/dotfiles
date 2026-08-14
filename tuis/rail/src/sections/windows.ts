import { fmtElapsed, line } from "../cells.js";
import type { Agent, Window } from "../data.js";
import type { Palette } from "../theme.js";

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

// Two orthogonal channels, never mixed: the accent-filled chip means only
// "you are here"; a colored title always means agent state. Plain windows
// stay dim, the current window's title reads at full text strength.
export function windowRows(
  windows: Window[],
  agentsByPane: Map<string, Agent>,
  palette: Palette,
  width: number,
): string[] {
  const railBg = palette.mantle;
  const rows: string[] = [];
  for (const win of windows) {
    const agent = win.paneIds
      .map((paneId) => agentsByPane.get(paneId))
      .find((a) => a !== undefined);
    const chipText =
      win.index < 10 ? ` ${win.index} ` : String(win.index).slice(0, 3);
    const chip = win.active
      ? { text: chipText, fg: palette.base, bg: palette.accent }
      : { text: chipText, fg: palette.dim2, bg: palette.surface0 };
    const titleFg = agent
      ? stateColor(agent.status, palette)
      : win.active
        ? palette.text
        : palette.dim2;
    rows.push(
      line(
        width,
        railBg,
        [
          { text: " ", fg: palette.text },
          chip,
          { text: " ", fg: palette.text },
          { text: win.name, fg: titleFg },
        ],
        agent
          ? { text: fmtElapsed(agent.elapsedSecs), fg: palette.dim }
          : undefined,
      ),
    );
    if (agent && agent.title) {
      rows.push(
        // Indented to start exactly under the title column.
        line(width, railBg, [
          { text: "     ", fg: palette.dim },
          { text: agent.title, fg: palette.dim },
        ]),
      );
    }
  }
  return rows;
}
