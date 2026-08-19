import { line, type Span } from "../cells.js";
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

// The tab row replaces the old divider between local tmux windows and the
// lower rail content. Agents hugs the left edge, Reviews is centered, and
// Tasks hugs the right edge; all three occupy one row above the lower scene.
// The tabs are square so their full-width backgrounds make the row itself
// the divider without introducing another hairline.
export function tabBar(
  activeTab: RailTabId,
  attention: RailTabAttention,
  palette: Palette,
  width: number,
): string {
  const bg = railBg(palette);
  const spans: Span[] = [];

  const tabWidth = (tab: (typeof RAIL_TABS)[number]): number =>
    tab.label.length + 2;
  // The rail's left exterior margin is Ghostty padding while its right
  // visual seam includes the rail gutter and tmux border. The one-cell
  // nudge compensates for that asymmetric frame around the odd-width tab.
  const reviewStart = Math.max(
    0,
    Math.floor((width - tabWidth(RAIL_TABS[1]!)) / 2) + 1,
  );
  const starts = [0, reviewStart, Math.max(0, width - tabWidth(RAIL_TABS[2]!))];
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
