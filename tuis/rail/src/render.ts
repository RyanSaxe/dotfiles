import { blank, line } from "./cells.js";
import type { Agent, RailData } from "./data.js";
import { elsewhereRows } from "./sections/elsewhere.js";
import { hairline, header } from "./sections/header.js";
import {
  MASCOT_ROWS,
  MIN_HEIGHT_FOR_MASCOT,
  mascotFooter,
} from "./sections/mascot.js";
import { windowRows } from "./sections/windows.js";
import type { Palette } from "./theme.js";

// Pure frame renderer: RailData -> exactly `height` ANSI lines of `width`
// cells. The daemon and the look-spike share this path verbatim.
export function renderRail(
  data: RailData,
  palette: Palette,
  width: number,
  height: number,
): string[] {
  const railBg = palette.mantle;

  const agentsByPane = new Map<string, Agent>();
  const elsewhere: Agent[] = [];
  for (const agent of data.agents) {
    if (agent.session === data.session) {
      agentsByPane.set(agent.paneId, agent);
    } else {
      elsewhere.push(agent);
    }
  }

  const body: string[] = [
    ...windowRows(data.windows, agentsByPane, data.acked, palette, width),
  ];
  if (elsewhere.length > 0) {
    body.push(hairline(palette, width));
    body.push(
      ...elsewhereRows(elsewhere, data.acked, data.hints, palette, width),
    );
  }

  const top = header(data.session, palette, width);
  const footer =
    height >= MIN_HEIGHT_FOR_MASCOT ? mascotFooter(palette, width) : [];
  // Bottom padding row mirrors the top one.
  const budget = height - top.length - footer.length - 1;

  let content = body;
  if (body.length > budget) {
    content = body.slice(0, Math.max(0, budget - 1));
    content.push(line(width, railBg, [{ text: "  ⋯", fg: palette.dim }]));
  }
  while (content.length < budget) content.push(blank(width, railBg));

  return [...top, ...content, ...footer, blank(width, railBg)];
}
