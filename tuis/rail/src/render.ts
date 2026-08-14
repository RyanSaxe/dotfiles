import { blank, line } from "./cells.js";
import type { Agent, RailData } from "./data.js";
import { elsewhereRows } from "./sections/elsewhere.js";
import { hairline, header, railBg } from "./sections/header.js";
import { MIN_HEIGHT_FOR_MASCOT, mascotFooter } from "./sections/mascot.js";
import { windowRows, type RailRow } from "./sections/windows.js";
import { bg as bgEsc, blend, RESET, type Palette } from "./theme.js";

// Keys that page the rail (tmux binds run `rail page up|down`); shown in
// the pagination indicators.
const PAGE_UP_KEY = "⌥,";
const PAGE_DOWN_KEY = "⌥.";

function indicator(palette: Palette, width: number, text: string): string {
  const pad = Math.max(0, Math.floor((width - text.length) / 2));
  return line(width, railBg(palette), [
    { text: " ".repeat(pad) + text, fg: palette.dim },
  ]);
}

// Pure frame renderer: RailData -> exactly `height` ANSI lines of `width`
// cells. The daemon and the look-spike share this path verbatim.
export function renderRail(
  data: RailData,
  palette: Palette,
  width: number,
  height: number,
): string[] {
  const bg = railBg(palette);
  // The last column is a content-background gutter (appended at the end):
  // together with the one-cell tmux border beside it, the slab and its
  // hairlines end exactly two cells (~19pt at font-size 16, the frame's
  // spacing unit) before the content pane's first character.
  const inner = width - 1;

  const agentsByPane = new Map<string, Agent>();
  const elsewhere: Agent[] = [];
  for (const agent of data.agents) {
    if (agent.session === data.session) {
      agentsByPane.set(agent.paneId, agent);
    } else {
      elsewhere.push(agent);
    }
  }

  // Every item row is preceded by a blank spacer — the breathing room is
  // part of the design and never collapses; crowding is handled by
  // pagination instead.
  const body: RailRow[] = [
    ...windowRows(data.windows, agentsByPane, data.acked, palette, inner),
  ];
  if (elsewhere.length > 0) {
    body.push({ text: blank(inner, bg), item: false });
    body.push({
      text: hairline(palette, inner, blend(palette.notify, bg, 0.5)),
      item: false,
    });
    body.push(
      ...elsewhereRows(elsewhere, data.acked, data.hints, palette, inner),
    );
  }

  const top = header(data.session, palette, inner);
  const footer =
    height >= MIN_HEIGHT_FOR_MASCOT
      ? mascotFooter(palette, inner, data.sprite)
      : [];
  // Bottom padding row mirrors the top of the footer.
  const budget = height - top.length - footer.length - 1;

  let content: string[];
  if (body.length <= budget) {
    content = body.map((row) => row.text);
  } else {
    // Paginate: indicator rows sit at fixed slots — directly under the
    // header rule and directly above the footer hairline — so the layout
    // stays symmetric on every page.
    const visible = Math.max(1, budget - 2);
    const maxPage = Math.floor((body.length - 1) / visible);
    const page = Math.min(Math.max(0, data.page), maxPage);
    const slice = body.slice(page * visible, page * visible + visible);
    const hiddenAbove = body
      .slice(0, page * visible)
      .filter((row) => row.item).length;
    const hiddenBelow = body
      .slice(page * visible + visible)
      .filter((row) => row.item).length;
    content = [
      hiddenAbove > 0
        ? indicator(palette, inner, `▲ +${hiddenAbove}  ${PAGE_UP_KEY}`)
        : blank(inner, bg),
      ...slice.map((row) => row.text),
      hiddenBelow > 0
        ? indicator(palette, inner, `▼ +${hiddenBelow}  ${PAGE_DOWN_KEY}`)
        : blank(inner, bg),
    ];
  }
  while (content.length < budget) content.push(blank(inner, bg));

  const gutter = bgEsc(palette.base) + " " + RESET;
  return [...top, ...content, ...footer, blank(inner, bg)].map(
    (row) => row + gutter,
  );
}
