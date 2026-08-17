import { blank, hintRow } from "./cells.js";
import type { Agent, RailData } from "./data.js";
import { elsewhereRows } from "./sections/elsewhere.js";
import { header, sectionHairline } from "./sections/header.js";
import {
  FOOTER_ROWS,
  MIN_HEIGHT_FOR_MASCOT,
  mascotFooter,
} from "./sections/mascot.js";
import type { RailRow } from "./sections/rows.js";
import { windowRows } from "./sections/windows.js";
import { bg as bgEsc, railBg, RESET, type Palette } from "./theme.js";

// Keys that page the rail (tmux binds run `rail page up|down`); shown in
// the footer pagination hint.
const PAGE_UP_KEY = "⌥,";
const PAGE_DOWN_KEY = "⌥.";

// The slab is 22 content cells; these two crust columns after them are
// the visible right margin (the colorless tmux border beside them reads
// as part of the gap). daemon.ts derives the pane width from this.
export const GUTTER_COLS = 1;

// Pure frame renderer: RailData -> exactly `height` ANSI lines of `width`
// cells. The daemon and the look-spike share this path verbatim.
export function renderRail(
  data: RailData,
  palette: Palette,
  width: number,
  height: number,
): string[] {
  const bg = railBg(palette);
  // The gutter (appended at the end) stops hairlines and text one cell
  // short of the slab's edge; the crust pane-border column supplies the
  // second, so text still rests ~19pt (two cells at font-size 16) from
  // the content surface — mirroring the frame crust on the rail's left.
  const inner = width - GUTTER_COLS;

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
    body.push({ text: sectionHairline(palette, inner), item: false });
    body.push(
      ...elsewhereRows(elsewhere, data.acked, data.hints, palette, inner),
    );
  }

  const top = header(data.session, palette, inner, data.prefixHeld);
  // The footer is reserved only when there is a sprite to put in it —
  // no mascot, or the driving client can't render kitty graphics, and
  // the rows go to content instead (an overflow hint then borrows the
  // bottom row exactly like a short pane).
  const hasFooter = data.sprite !== null && height >= MIN_HEIGHT_FOR_MASCOT;
  // No blank row below the sprite: the 19pt bottom frame is the sprite's
  // lower margin (~one cell), matching the blank row above it — so the
  // mascot reads centered between the footer hairline and the window edge.
  const budget = height - top.length - (hasFooter ? FOOTER_ROWS : 0);

  let content: string[];
  let pageHint = "";
  if (body.length <= budget) {
    content = body.map((row) => row.text);
  } else {
    // Paginate by units — an item plus the furniture rows above it — so
    // every page opens with the standard one-row gap under the header rule
    // and closes on an item. The hint lives in the footer, not the list.
    const units: RailRow[][] = [];
    let unit: RailRow[] = [];
    for (const row of body) {
      unit.push(row);
      if (row.item) {
        units.push(unit);
        unit = [];
      }
    }
    const pages: RailRow[][] = [];
    let current: RailRow[] = [];
    for (const u of units) {
      if (current.length > 0 && current.length + u.length > budget) {
        pages.push(current);
        current = [];
      }
      current.push(...u);
    }
    if (current.length > 0) pages.push(current);
    const page = Math.min(Math.max(0, data.page), pages.length - 1);
    const shown = pages[page] ?? [];
    const items = (rows: RailRow[]) => rows.filter((row) => row.item).length;
    const hiddenAbove = pages.slice(0, page).reduce((n, p) => n + items(p), 0);
    const hiddenBelow = pages.slice(page + 1).reduce((n, p) => n + items(p), 0);
    content = shown.slice(0, budget).map((row) => row.text);
    const hints: string[] = [];
    if (hiddenAbove > 0) hints.push(`▲ +${hiddenAbove} ${PAGE_UP_KEY}`);
    if (hiddenBelow > 0) hints.push(`▼ +${hiddenBelow} ${PAGE_DOWN_KEY}`);
    pageHint = hints.join("   ");
  }
  while (content.length < budget) content.push(blank(inner, bg));
  // Short panes have no footer to carry the hint; borrow the bottom row.
  if (!hasFooter && pageHint) {
    content[budget - 1] = hintRow(palette, inner, pageHint);
  }

  const footer = hasFooter
    ? mascotFooter(palette, inner, data.sprite, pageHint)
    : [];
  const gutter = bgEsc(bg) + "  " + RESET;
  return [...top, ...content, ...footer].map((row) => row + gutter);
}
