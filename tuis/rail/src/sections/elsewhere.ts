import { blank, fmtElapsed, line } from "../cells.js";
import type { Agent } from "../data.js";
import { blend, type Palette } from "../theme.js";
import { railBg } from "./header.js";
import { pill, stateColor } from "./windows.js";

// How much of a foreground color survives in the elsewhere section: the
// whole section sits at one uniform dim level — urgency order and hue carry
// attention, never extra brightness tiers.
const ELSEWHERE_KEEP = 0.55;

const URGENCY: Record<Agent["status"], number> = {
  waiting: 0,
  working: 1,
  done: 2,
};

// Acked rows sort after everything: their news has been seen.
export function sortElsewhere(agents: Agent[], acked: Set<string>): Agent[] {
  const rank = (agent: Agent) =>
    acked.has(agent.paneId) ? 3 : URGENCY[agent.status];
  return [...agents].sort(
    (a, b) => rank(a) - rank(b) || b.updatedTs - a.updatedTs,
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
  acked: Set<string>,
  hints: Map<string, string>,
  palette: Palette,
  width: number,
  spacious: boolean,
): string[] {
  const bg = railBg(palette);
  const dim = blend(palette.dim, bg, ELSEWHERE_KEEP);
  const dim2 = blend(palette.dim2, bg, ELSEWHERE_KEEP);
  const chipBg = blend(palette.surface0, bg, ELSEWHERE_KEEP);
  const rows: string[] = [];
  for (const agent of sortElsewhere(agents, acked)) {
    const { project, name } = label(agent);
    const nameFg = acked.has(agent.paneId)
      ? dim2
      : blend(stateColor(agent.status, palette), bg, ELSEWHERE_KEEP);
    const hint = hints.get(agent.paneId);
    if (spacious) rows.push(blank(width, bg));
    rows.push(
      line(
        width,
        bg,
        [
          { text: " ", fg: dim },
          // The jump pill mirrors the window pills exactly — same shape,
          // blended colors; alt+; then this letter lands on the pane.
          ...(hint ? pill(hint, dim2, chipBg, bg) : [{ text: "   ", fg: dim }]),
          { text: " ", fg: dim },
          { text: project, fg: dim },
          { text: name, fg: nameFg },
        ],
        { text: fmtElapsed(agent.elapsedSecs), fg: dim },
      ),
    );
  }
  return rows;
}
