// Pokemon sprite via kitty-graphics Unicode placeholders — the
// multiplexer-safe half of the protocol. The PNG is transmitted once as a
// VIRTUAL placement (U=1); the rail frame then contains placeholder cells
// (U+10EEEE) whose foreground color encodes the image id and whose
// combining diacritics encode each cell's row/column. To tmux those are
// ordinary styled text, so redraws, window switches, detaches, and the
// toggle all carry the sprite exactly like text. Nothing ever needs
// deleting: no cells, no image.

import { readFileSync } from "node:fs";
import { closeSync, openSync, writeSync } from "node:fs";

// Footer block the sprite is scaled over. Terminal cells are ~1:2, so
// 14x7 cells is roughly square — right for the 96x96 sprites.
export const SPRITE_COLS = 14;
export const SPRITE_ROWS = 7;

// Row/column diacritics, indices 0..15, from kitty's
// rowcolumn-diacritics.txt (the spec's canonical table).
const DIACRITICS = [
  0x0305, 0x030d, 0x030e, 0x0310, 0x0312, 0x033d, 0x033e, 0x033f, 0x0346,
  0x034a, 0x034b, 0x034c, 0x0350, 0x0351, 0x0352, 0x0357,
];

const PLACEHOLDER = 0x10eeee;

// Image ids double as the placeholder foreground color (24-bit). The base
// keeps the rail clear of the small ids other tools (nvim image plugins)
// typically allocate from zero.
const ID_BASE = 0x72a100;
let nextId = ID_BASE;
const idBySprite = new Map<string, number>();

export function spriteId(spritePath: string): number {
  const existing = idBySprite.get(spritePath);
  if (existing !== undefined) return existing;
  const id = nextId++;
  idBySprite.set(spritePath, id);
  return id;
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
  try {
    const fd = openSync(tty, "w");
    writeSync(fd, payload);
    closeSync(fd);
    return true;
  } catch {
    return false;
  }
}
