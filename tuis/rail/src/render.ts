import { blank, line } from "./cells.js";
import type { Agent, RailData } from "./data.js";
import { elsewhereRows } from "./sections/elsewhere.js";
import { hairline, header, railBg } from "./sections/header.js";
import { MIN_HEIGHT_FOR_MASCOT, mascotFooter } from "./sections/mascot.js";
import { windowRows } from "./sections/windows.js";
import { blend, type Palette } from "./theme.js";

// Pure frame renderer: RailData -> exactly `height` ANSI lines of `width`
// cells. The daemon and the look-spike share this path verbatim.
export function renderRail(
  data: RailData,
  palette: Palette,
  width: number,
  height: number,
): string[] {
  const bg = railBg(palette);

  const agentsByPane = new Map<string, Agent>();
  const elsewhere: Agent[] = [];
  for (const agent of data.agents) {
    if (agent.session === data.session) {
      agentsByPane.set(agent.paneId, agent);
    } else {
      elsewhere.push(agent);
    }
  }

  // Section rows each start with their own blank spacer, so the gap under
  // a rule always equals the gap above the next one.
  const build = (spacious: boolean): string[] => {
    const body: string[] = [
      ...windowRows(
        data.windows,
        agentsByPane,
        data.acked,
        palette,
        width,
        spacious,
      ),
    ];
    if (elsewhere.length > 0) {
      if (spacious) body.push(blank(width, bg));
      body.push(hairline(palette, width, blend(palette.notify, bg, 0.5)));
      body.push(
        ...elsewhereRows(
          elsewhere,
          data.acked,
          data.hints,
          palette,
          width,
          spacious,
        ),
      );
    }
    return body;
  };

  const top = header(data.session, palette, width);
  const footer =
    height >= MIN_HEIGHT_FOR_MASCOT
      ? mascotFooter(palette, width, data.sprite)
      : [];
  // Bottom padding row mirrors the top one.
  const budget = height - top.length - footer.length - 1;

  // Adaptive density: breathe while there is room, tighten when the list
  // grows, and only then truncate — with a count, so nothing hides
  // silently.
  let content = build(true);
  if (content.length > budget) content = build(false);
  if (content.length > budget) {
    const hidden = content.length - Math.max(0, budget - 1);
    content = content.slice(0, Math.max(0, budget - 1));
    content.push(
      line(width, bg, [{ text: `  +${hidden} more`, fg: palette.dim }]),
    );
  }
  while (content.length < budget) content.push(blank(width, bg));

  return [...top, ...content, ...footer, blank(width, bg)];
}
