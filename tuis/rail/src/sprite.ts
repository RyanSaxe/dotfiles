// Pokemon sprite via kitty-graphics Unicode placeholders — the
// multiplexer-safe half of the protocol. The PNG is transmitted once as a
// VIRTUAL placement (U=1); the rail frame then contains placeholder cells
// (U+10EEEE) whose foreground color encodes the image id and whose
// combining diacritics encode each cell's row/column. To tmux those are
// ordinary styled text, so redraws, window switches, detaches, and the
// toggle all carry the sprite exactly like text. Nothing ever needs
// deleting: no cells, no image.

import { closeSync, openSync, readFileSync, writeSync } from "node:fs";

// Write raw bytes straight to a pane's tty, tolerating its death between
// the poll and the write. The daemon paints frames through this too.
export function writeTty(tty: string, payload: string): boolean {
  try {
    const fd = openSync(tty, "w");
    writeSync(fd, payload);
    closeSync(fd);
    return true;
  } catch {
    return false;
  }
}

// Footer block the sprite is scaled over. Terminal cells are roughly 1:2
// (9.6pt x 20.8pt at font-size 16), so 18x8 cells is ~173x166pt — near
// square, and 18 centers exactly in the 22-column rail (2 cols each side).
export const SPRITE_COLS = 18;
export const SPRITE_ROWS = 8;

// Row/column diacritics, indices 0..31, from kitty's
// rowcolumn-diacritics.txt (the spec's canonical table, in order).
const DIACRITICS = [
  0x0305, 0x030d, 0x030e, 0x0310, 0x0312, 0x033d, 0x033e, 0x033f, 0x0346,
  0x034a, 0x034b, 0x034c, 0x0350, 0x0351, 0x0352, 0x0357, 0x035b, 0x0363,
  0x0364, 0x0365, 0x0366, 0x0367, 0x0368, 0x0369, 0x036a, 0x036b, 0x036c,
  0x036d, 0x036e, 0x036f, 0x0483, 0x0484,
];

const PLACEHOLDER = 0x10eeee;

// A sprite larger than the diacritic table would index undefined and
// throw NaN code points deep inside the render loop — fail at load time
// with a legible error instead.
if (SPRITE_COLS > DIACRITICS.length || SPRITE_ROWS > DIACRITICS.length) {
  throw new Error(
    `sprite grid ${SPRITE_COLS}x${SPRITE_ROWS} exceeds the ${DIACRITICS.length}-entry diacritic table`,
  );
}

// Image ids double as the placeholder foreground color (24-bit). Derived
// from a hash of the sprite path so an id is STABLE across daemon
// restarts — a restart-reset counter would hand one pokemon's id to
// another, and stale placeholders would show slices of the wrong sprite
// until retransmission. The offset keeps ids clear of the small ones
// other tools (nvim image plugins) allocate from zero.
export function spriteId(spritePath: string): number {
  let hash = 0x811c9dc5;
  for (let i = 0; i < spritePath.length; i++) {
    hash ^= spritePath.charCodeAt(i);
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }
  return 0x100000 + (hash % 0xefffff);
}

export function idToHex(id: number): string {
  return `#${id.toString(16).padStart(6, "0")}`;
}

// One frame row of the placeholder block: every cell is U+10EEEE + row
// diacritic + column diacritic. Rendered as a single span colored with the
// image id.
export function placeholderRow(row: number): string {
  let cells = "";
  for (let col = 0; col < SPRITE_COLS; col++) {
    cells += String.fromCodePoint(
      PLACEHOLDER,
      DIACRITICS[row]!,
      DIACRITICS[col]!,
    );
  }
  return cells;
}

// ----- transmission ------------------------------------------------------

// tmux passthrough: DCS-wrap a sequence with every inner ESC doubled.
function wrapTmux(sequence: string): string {
  return `\x1bPtmux;${sequence.replaceAll("\x1b", "\x1b\x1b")}\x1b\\`;
}

const CHUNK = 4096;
const spriteBytes = new Map<string, Buffer | null>();

function readSprite(path: string): Buffer | null {
  if (!spriteBytes.has(path)) {
    try {
      spriteBytes.set(path, readFileSync(path));
    } catch {
      spriteBytes.set(path, null);
    }
  }
  return spriteBytes.get(path) ?? null;
}

// Send the PNG as a virtual placement through a VISIBLE pane's tty (tmux
// only forwards passthrough for visible panes). Terminals drop image data
// on restart, so callers re-send on a slow interval.
export function transmitSprite(tty: string, spritePath: string): boolean {
  const png = readSprite(spritePath);
  if (!png) return false;
  const id = spriteId(spritePath);
  const b64 = png.toString("base64");
  let payload = "";
  for (let offset = 0; offset < b64.length; offset += CHUNK) {
    const chunk = b64.slice(offset, offset + CHUNK);
    const last = offset + CHUNK >= b64.length;
    const control =
      offset === 0
        ? `a=T,U=1,f=100,q=2,i=${id},c=${SPRITE_COLS},r=${SPRITE_ROWS},m=${last ? 0 : 1}`
        : `m=${last ? 0 : 1}`;
    payload += wrapTmux(`\x1b_G${control};${chunk}\x1b\\`);
  }
  return writeTty(tty, payload);
}
