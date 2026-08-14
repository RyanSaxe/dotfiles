import { line } from "../cells.js";
import type { Palette } from "../theme.js";

// The rail's slab color: the darkest palette tier, so the sidebar fuses
// with the window frame it leans against.
export const railBg = (palette: Palette): string => palette.crust;

// Session identity: the name is the rail's first cell — the window's
// symmetric padding places it exactly at (19, 19) — over a full-width
// accent rule.
export function header(
  session: string,
  palette: Palette,
  width: number,
): string[] {
  const bg = railBg(palette);
  return [
    line(width, bg, [{ text: session, fg: palette.lavender }]),
    // Heavy rule: the header's accent line carries more weight than the
    // section hairlines below it.
    line(width, bg, [{ text: "━".repeat(width), fg: palette.accent }]),
  ];
}

// Thin rule, full width — every line in the rail shares one span.
export function hairline(palette: Palette, width: number, fg: string): string {
  return line(width, railBg(palette), [{ text: "─".repeat(width), fg }]);
}
