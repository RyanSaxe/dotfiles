import { blank, line } from "../cells.js";
import {
  idToHex,
  placeholderRow,
  SPRITE_COLS,
  SPRITE_ROWS,
} from "../sprite.js";
import { blend, type Palette } from "../theme.js";
import { hairline, railBg } from "./header.js";

// Reserved footer: the mascot's home. When a sprite id is present the
// footer rows carry kitty Unicode-placeholder cells and the terminal draws
// the real pixel art over them; without one (no capable client attached,
// no sprite cached) the footer stays blank — never boxes, never escapes.
export const MASCOT_ROWS = SPRITE_ROWS + 1;

// Only reserve the footer when the pane is tall enough that content
// doesn't starve for it.
export const MIN_HEIGHT_FOR_MASCOT = 24;

export function mascotFooter(
  palette: Palette,
  width: number,
  spriteIdValue: number | null,
): string[] {
  const bg = railBg(palette);
  const rows: string[] = [
    hairline(palette, width, blend(palette.notify, bg, 0.5)),
    blank(width, bg),
  ];
  if (spriteIdValue === null || width < SPRITE_COLS + 2) {
    for (let i = 0; i < SPRITE_ROWS; i++) rows.push(blank(width, bg));
    return rows;
  }
  const leftPad = Math.floor((width - SPRITE_COLS) / 2);
  const fg = idToHex(spriteIdValue);
  for (let row = 0; row < SPRITE_ROWS; row++) {
    rows.push(
      line(width, bg, [
        { text: " ".repeat(leftPad), fg: palette.dim },
        { text: placeholderRow(row), fg },
      ]),
    );
  }
  return rows;
}
