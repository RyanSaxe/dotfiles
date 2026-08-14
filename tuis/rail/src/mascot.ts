// Mascot placement: the cached sprite PNG rendered into the rail's footer
// via the kitty graphics protocol, tunneled through tmux passthrough.
//
// Discipline that keeps images from ghosting over the wrong content:
//   - place only while the rail's window is visible on an attached client
//   - delete the placement the moment visibility is lost (requires
//     tmux allow-passthrough all, so deletes escape from hidden panes)
//   - one stable image id per pane; delete before every re-place
// Terminals without kitty graphics ignore the APC — the footer stays empty.

import { readFileSync } from "node:fs";
import { closeSync, openSync, writeSync } from "node:fs";

import type { Pane } from "./data.js";
import { MASCOT_ROWS, MIN_HEIGHT_FOR_MASCOT } from "./sections/mascot.js";

// Sprite cells: rows of the footer it fills; kitty preserves aspect when
// only r is given, so a square sprite lands near rows*2 columns wide.
const SPRITE_ROWS = MASCOT_ROWS - 1;
const SPRITE_COLS = SPRITE_ROWS * 2;
const CHUNK = 4096;

// tmux passthrough: DCS-wrap the sequence with every ESC doubled.
function wrapTmux(sequence: string): string {
  return `\x1bPtmux;${sequence.replaceAll("\x1b", "\x1b\x1b")}\x1b\\`;
}

function apc(payload: string): string {
  return wrapTmux(`\x1b_G${payload}\x1b\\`);
}

function imageId(pane: Pane): number {
  // Pane ids are "%<n>"; offset keeps rail ids clear of other tools.
  return 700000 + Number(pane.paneId.slice(1));
}

function deleteSeq(pane: Pane): string {
  return apc(`a=d,d=i,i=${imageId(pane)},q=2`);
}

function placeSeq(pane: Pane, png: Buffer): string {
  const id = imageId(pane);
  const row = pane.height - MASCOT_ROWS + 1;
  const col = Math.max(1, Math.floor((pane.width - SPRITE_COLS) / 2) + 1);
  const b64 = png.toString("base64");
  const parts: string[] = [deleteSeq(pane), `\x1b[${row};${col}H`];
  for (let offset = 0; offset < b64.length; offset += CHUNK) {
    const chunk = b64.slice(offset, offset + CHUNK);
    const last = offset + CHUNK >= b64.length;
    const control =
      offset === 0
        ? `a=T,f=100,i=${id},q=2,r=${SPRITE_ROWS},m=${last ? 0 : 1}`
        : `m=${last ? 0 : 1}`;
    parts.push(apc(`${control};${chunk}`));
  }
  return parts.join("");
}

interface Placement {
  key: string;
  visible: boolean;
  tty: string;
  paneId: string;
}

const placements = new Map<string, Placement>();
const sprites = new Map<string, Buffer>();

function spriteBytes(path: string): Buffer | null {
  const cached = sprites.get(path);
  if (cached) return cached;
  try {
    const bytes = readFileSync(path);
    sprites.set(path, bytes);
    return bytes;
  } catch {
    return null;
  }
}

function writeTty(tty: string, payload: string): void {
  try {
    const fd = openSync(tty, "w");
    writeSync(fd, payload);
    closeSync(fd);
  } catch {
    // Pane vanished; state is pruned by syncMascots' alive-sweep.
  }
}

// Reconcile one rail pane's mascot with what should be on screen.
export function syncMascot(
  pane: Pane,
  spritePath: string | null,
  visible: boolean,
): void {
  const tall = pane.height >= MIN_HEIGHT_FOR_MASCOT;
  const shouldShow = visible && tall && spritePath !== null;
  const key = `${spritePath}\x1f${pane.width}\x1f${pane.height}`;
  const placement = placements.get(pane.paneId);

  if (!shouldShow) {
    if (placement?.visible) {
      writeTty(pane.tty, deleteSeq(pane));
      placements.set(pane.paneId, {
        key,
        visible: false,
        tty: pane.tty,
        paneId: pane.paneId,
      });
    }
    return;
  }
  if (placement?.visible && placement.key === key) return;
  const png = spriteBytes(spritePath);
  if (!png) return;
  writeTty(pane.tty, placeSeq(pane, png));
  placements.set(pane.paneId, {
    key,
    visible: true,
    tty: pane.tty,
    paneId: pane.paneId,
  });
}

export function forgetPane(paneId: string): void {
  placements.delete(paneId);
}

// Daemon shutdown: leave no image behind, anywhere.
export function releaseAllMascots(): void {
  for (const placement of placements.values()) {
    if (placement.visible) {
      const id = 700000 + Number(placement.paneId.slice(1));
      writeTty(placement.tty, apc(`a=d,d=i,i=${id},q=2`));
    }
  }
  placements.clear();
}
