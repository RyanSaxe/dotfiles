import { line } from "../cells.js";
import { blend, railBg, type Palette } from "../theme.js";

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

// Thin rule, full width, in the sections' one hairline color — every
// divider below the header shares this look.
export function sectionHairline(palette: Palette, width: number): string {
  const bg = railBg(palette);
  return line(width, bg, [
    { text: "─".repeat(width), fg: blend(palette.notify, bg, 0.5) },
  ]);
}
