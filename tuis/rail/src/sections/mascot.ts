import { blank, hintRow, line } from "../cells.js";
import {
  idToHex,
  placeholderRow,
  SPRITE_COLS,
  SPRITE_ROWS,
} from "../sprite.js";
import { railBg, type Palette } from "../theme.js";

// The mascot's home, reserved by the renderer only when a sprite id is
// present: the footer rows carry kitty Unicode-placeholder cells and the
// terminal draws the real pixel art over them. Without a sprite the
// renderer skips the footer entirely and content gets the rows.
// Rows: hint/blank row + the sprite block. The square tab row is the rail's
// only lower-section divider; the mascot no longer gets a second hairline.
export const FOOTER_ROWS = SPRITE_ROWS + 1;

// Only reserve the footer when the pane is tall enough that content
// doesn't starve for it.
export const MIN_HEIGHT_FOR_MASCOT = 24;

export function mascotFooter(
  palette: Palette,
  width: number,
  spriteIdValue: number | null,
  pageHint = "",
): string[] {
  const bg = railBg(palette);
  const rows: string[] = [
    // The row above the sprite doubles as the pagination hint's home — out
    // of the list, with air on both sides.
    pageHint ? hintRow(palette, width, pageHint) : blank(width, bg),
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
