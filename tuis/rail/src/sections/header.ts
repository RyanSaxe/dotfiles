import { displayWidth, line, type Span } from "../cells.js";
import type { RailTabAttention, RailTabId } from "../tabs.js";
import { RAIL_TABS } from "../tabs.js";
import { blend, DIM_KEEP, railBg, type Palette } from "../theme.js";

// Session identity: the name is the rail's first cell — the window's
// symmetric padding places it exactly at (19, 19) — over a full-width
// accent rule. While a prefix chord is mid-flight the name flips to the
// accent, making the pending-key state visible at a glance.
export function header(
  session: string,
  palette: Palette,
  width: number,
  prefixHeld: boolean,
): string[] {
  const bg = railBg(palette);
  return [
    line(width, bg, [
      { text: session, fg: prefixHeld ? palette.accent : palette.lavender },
    ]),
    // Heavy rule: the header's accent line is the rail's only rule.
    line(width, bg, [{ text: "━".repeat(width), fg: palette.accent }]),
  ];
}

// The mascot owns this lower-footer rule. It is deliberately not used above
// the tab row: the square tabs are that divider.
export function sectionHairline(palette: Palette, width: number): string {
  const bg = railBg(palette);
  return line(width, bg, [
    { text: "─".repeat(width), fg: blend(palette.notify, bg, 0.5) },
  ]);
}

// The tab row replaces the old divider between local tmux windows and the
// lower rail content. Chips keep registry order, and the gaps come from the
// actual chip widths rather than a fixed number of tab positions.
// The tabs are square so their full-width backgrounds make the row itself
// the divider without introducing another hairline.
function tabStarts(width: number, widths: readonly number[]): number[] {
  if (widths.length === 0) return [];
  if (widths.length === 1) return [0];

  const total = widths.reduce((sum, tabWidth) => sum + tabWidth, 0);
  const gapCount = widths.length - 1;
  const free = Math.max(0, width - total);
  const starts: number[] = [];
  let cursor = 0;
  let allocated = 0;
  for (const [index, tabWidth] of widths.entries()) {
    starts.push(cursor);
    if (index === widths.length - 1) break;
    const nextAllocated = Math.round((free * (index + 1)) / gapCount);
    cursor += tabWidth + nextAllocated - allocated;
    allocated = nextAllocated;
  }
  return starts;
}

export function tabBar(
  activeTab: RailTabId,
  attention: RailTabAttention,
  palette: Palette,
  width: number,
): string {
  const bg = railBg(palette);
  const spans: Span[] = [];

  const tabWidth = (tab: (typeof RAIL_TABS)[number]): number =>
    displayWidth(tab.label) + 2;
  const starts = tabStarts(width, RAIL_TABS.map(tabWidth));
  let cursor = 0;

  for (const [index, tab] of RAIL_TABS.entries()) {
    const active = tab.id === activeTab;
    const chipBg = active
      ? palette.accent
      : blend(palette.surface0, bg, DIM_KEEP);
    const fg = active
      ? palette.base
      : attention[tab.id]
        ? palette.red
        : palette.dim2;
    const start = starts[index] ?? cursor;
    if (start > cursor)
      spans.push({ text: " ".repeat(start - cursor), fg: bg });
    spans.push({ text: ` ${tab.label} `, fg, bg: chipBg });
    cursor = start + tabWidth(tab);
  }
  return line(width, bg, spans);
}
