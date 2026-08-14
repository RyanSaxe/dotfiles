import { blank, line } from "../cells.js";
import type { Agent } from "../data.js";
import { blend, DIM_KEEP, railBg, type Palette } from "../theme.js";
import {
  agentRank,
  elapsedSpan,
  pill,
  stateColor,
  type RailRow,
} from "./rows.js";

// Urgency first, acked last, newest activity breaking ties.
function sortElsewhere(agents: Agent[], acked: Set<string>): Agent[] {
  return [...agents].sort(
    (a, b) =>
      agentRank(a, acked) - agentRank(b, acked) || b.updatedTs - a.updatedTs,
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

// The whole section sits at one uniform dim level (DIM_KEEP) — urgency
// order and hue carry attention, never extra brightness tiers.
export function elsewhereRows(
  agents: Agent[],
  acked: Set<string>,
  hints: Map<string, string>,
  palette: Palette,
  width: number,
): RailRow[] {
  const bg = railBg(palette);
  const dim = blend(palette.dim, bg, DIM_KEEP);
  const dim2 = blend(palette.dim2, bg, DIM_KEEP);
  const chipBg = blend(palette.surface0, bg, DIM_KEEP);
  const rows: RailRow[] = [];
  for (const agent of sortElsewhere(agents, acked)) {
    const { project, name } = label(agent);
    const nameFg = acked.has(agent.paneId)
      ? dim2
      : blend(stateColor(agent.status, palette), bg, DIM_KEEP);
    const hint = hints.get(agent.paneId);
    rows.push({ text: blank(width, bg), item: false });
    rows.push({
      text: line(
        width,
        bg,
        [
          // The jump pill mirrors the window pills exactly — same shape,
          // blended colors; alt+; then this letter lands on the pane.
          ...(hint ? pill(hint, dim2, chipBg, bg) : [{ text: "   ", fg: dim }]),
          { text: " ", fg: dim },
          { text: project, fg: dim },
          { text: name, fg: nameFg },
        ],
        elapsedSpan(agent, acked, palette),
      ),
      item: true,
    });
  }
  return rows;
}
