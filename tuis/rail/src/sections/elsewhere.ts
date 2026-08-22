import type { Agent } from "../data.js";
import { blend, DIM_KEEP, railBg, type Palette } from "../theme.js";
import {
  elapsedSpan,
  pill,
  sortByUrgency,
  spacedItem,
  stateColor,
  type RailRow,
} from "./rows.js";

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
  for (const [index, agent] of sortByUrgency(agents, acked).entries()) {
    const { project, name } = label(agent);
    // The rail is narrow, so state colour lives on the FIRST stable token —
    // the one that survives truncation. A trailing worktree name is the
    // first thing to get clipped, which is exactly where the colour used
    // to be.
    const projectFg = acked.has(agent.paneId)
      ? dim2
      : blend(stateColor(agent.status, palette), bg, DIM_KEEP);
    // The daemon hands out jump digits by display position, so the assigned
    // digit and the row's own number are the same thing — read the map where
    // it has one, so the pill can only ever say what the key will do.
    const hint = hints.get(agent.paneId) ?? String(index + 1);
    rows.push(
      ...spacedItem(
        width,
        bg,
        [
          // The jump pill mirrors the window pills exactly — same shape,
          // blended colors; alt+space then this digit lands on the pane.
          // Only 1-9 are in the tmux table, so a tenth pill is a position
          // rather than a keystroke — the list keeps counting where the
          // keyboard stops, instead of trailing off into blank cells.
          ...pill(hint, dim2, chipBg, bg),
          { text: " ", fg: dim },
          { text: project, fg: projectFg },
          { text: name, fg: dim },
        ],
        elapsedSpan(agent, acked, palette),
      ),
    );
  }
  return rows;
}
