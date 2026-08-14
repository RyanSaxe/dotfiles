import { blank } from "../cells.js";
import type { Palette } from "../theme.js";
import { hairline } from "./header.js";

// Reserved footer: the mascot's home. Rows never enter it. The sprite
// itself arrives via the kitty graphics protocol (real pixel art, sized to
// the pane); until that lands the footer holds its space empty.
// TODO(R4): render the cached pokemon sprite PNG here.
export const MASCOT_ROWS = 8;

// Only reserve the footer when the pane is tall enough that content
// doesn't starve for it.
export const MIN_HEIGHT_FOR_MASCOT = 24;

export function mascotFooter(palette: Palette, width: number): string[] {
  const rows: string[] = [hairline(palette, width)];
  for (let i = 0; i < MASCOT_ROWS; i++) rows.push(blank(width, palette.mantle));
  return rows;
}
