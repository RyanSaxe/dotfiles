import { blank, line } from "../cells.js";
import type { Palette } from "../theme.js";

// Session identity: name in lavender over a full-width accent rule —
// the rail's only use of the accent outside the current-window chip.
export function header(
  session: string,
  palette: Palette,
  width: number,
): string[] {
  const railBg = palette.mantle;
  return [
    blank(width, railBg),
    line(width, railBg, [
      { text: " ", fg: palette.text },
      { text: session, fg: palette.lavender },
    ]),
    // Heavy rule: the header's accent line carries more weight than the
    // section hairlines, mirroring the gold standard's 2px vs 1px borders.
    line(width, railBg, [
      { text: " " + "━".repeat(width - 2), fg: palette.accent },
    ]),
  ];
}

export function hairline(palette: Palette, width: number): string {
  return line(width, palette.mantle, [
    { text: "  " + "─".repeat(width - 4), fg: palette.surface0 },
  ]);
}
