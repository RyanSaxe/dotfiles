import { fmtElapsed, line } from "../cells.js";
import type { Agent } from "../data.js";
import { blend, type Palette } from "../theme.js";
import { stateColor } from "./windows.js";

// How much of a foreground color survives in the elsewhere section: the
// whole section sits at one uniform dim level — urgency order and hue carry
// attention, never extra brightness tiers.
const ELSEWHERE_KEEP = 0.55;

const URGENCY: Record<Agent["status"], number> = {
  waiting: 0,
  working: 1,
  done: 2,
};

export function sortElsewhere(agents: Agent[]): Agent[] {
  return [...agents].sort(
    (a, b) =>
      URGENCY[a.status] - URGENCY[b.status] || b.updatedTs - a.updatedTs,
  );
}

// Row label: project/worktree, except the main worktree (named like the
// project) reads better as project/branch.
function label(agent: Agent): { project: string; name: string } {
  const name =
    agent.worktree && agent.worktree !== agent.session
      ? agent.worktree
      : agent.branch || agent.worktree || "?";
  return { project: `${agent.session}/`, name };
}

export function elsewhereRows(
  agents: Agent[],
  palette: Palette,
  width: number,
): string[] {
  const railBg = palette.mantle;
  const dim = blend(palette.dim, railBg, ELSEWHERE_KEEP);
  const rows: string[] = [];
  for (const agent of sortElsewhere(agents)) {
    const { project, name } = label(agent);
    const state = blend(
      stateColor(agent.status, palette),
      railBg,
      ELSEWHERE_KEEP,
    );
    rows.push(
      line(
        width,
        railBg,
        [
          { text: " ", fg: dim },
          { text: project, fg: dim },
          { text: name, fg: state },
        ],
        { text: fmtElapsed(agent.elapsedSecs), fg: dim },
      ),
    );
    if (agent.title) {
      rows.push(
        line(width, railBg, [
          { text: " ", fg: dim },
          { text: agent.title, fg: dim },
        ]),
      );
    }
  }
  return rows;
}
