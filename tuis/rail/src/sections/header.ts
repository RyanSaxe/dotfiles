import { line } from "../cells.js";
import type { RailTabId } from "../tabs.js";
import { RAIL_TABS } from "../tabs.js";
import { pill } from "./rows.js";
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
    // Heavy rule: the header's accent line carries more weight than the
    // section hairlines below it.
    line(width, bg, [{ text: "━".repeat(width), fg: palette.accent }]),
  ];
}

// The tab row replaces the old divider between local tmux windows and the
// lower rail content. It is centered and occupies exactly one row, so every
// tab keeps the same scroll/page geometry while the window list remains
// visible above it.
export function tabBar(
  activeTab: RailTabId,
  reviewNeedsAttention: boolean,
  palette: Palette,
  width: number,
): string {
  const bg = railBg(palette);
  const total =
    RAIL_TABS.reduce((sum, tab) => sum + tab.label.length + 2, 0) +
    RAIL_TABS.length -
    1;
  const pad = Math.max(0, Math.floor((width - total) / 2));
  const spans = [{ text: " ".repeat(pad), fg: bg }];

  for (const [index, tab] of RAIL_TABS.entries()) {
    const active = tab.id === activeTab;
    const chipBg = active
      ? palette.accent
      : blend(palette.surface0, bg, DIM_KEEP);
    const fg = active
      ? palette.base
      : tab.id === "review" && reviewNeedsAttention
        ? palette.red
        : palette.dim2;
    spans.push(...pill(tab.label, fg, chipBg, bg));
    if (index < RAIL_TABS.length - 1) spans.push({ text: " ", fg: bg });
  }
  return line(width, bg, spans);
}

// Thin rule, full width, in the sections' one hairline color — every
// divider below the header shares this look.
export function sectionHairline(palette: Palette, width: number): string {
  const bg = railBg(palette);
  return line(width, bg, [
    { text: "─".repeat(width), fg: blend(palette.notify, bg, 0.5) },
  ]);
}
