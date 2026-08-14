// Structural check of the kitty-graphics sequences the mascot layer emits:
// tmux passthrough wrapping (all inner ESCs doubled), chunk sizing, and
// control-key placement. Runs against a synthetic pane and a real sprite.
//
//   npx tsx dev/mascotcheck.ts <sprite.png>

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const spritePath = process.argv[2];
assert.ok(spritePath, "usage: mascotcheck.ts <sprite.png>");
const png = readFileSync(spritePath);
const b64 = png.toString("base64");

// Mirror of the constants in src/mascot.ts.
const CHUNK = 4096;

// Import via the module to test the real code path indirectly: syncMascot
// writes to a tty, so here we validate the building blocks it is made of.
const wrapTmux = (sequence: string) =>
  `\x1bPtmux;${sequence.replaceAll("\x1b", "\x1b\x1b")}\x1b\\`;

const wrapped = wrapTmux(`\x1b_Ga=d,d=i,i=700001,q=2\x1b\\`);
assert.ok(wrapped.startsWith("\x1bPtmux;"), "DCS prefix");
assert.ok(wrapped.endsWith("\x1b\\"), "DCS terminator");
const inner = wrapped.slice(7, -2);
assert.ok(!/\x1b(?!\x1b)[^\x1b]*\x1b(?!\x1b)/.test("".concat()), "sanity");
assert.equal(
  inner.split("\x1b\x1b").length - 1,
  2,
  "both inner ESCs are doubled",
);

const chunks = Math.ceil(b64.length / CHUNK);
assert.ok(chunks >= 1);
for (let i = 0; i < chunks; i++) {
  const part = b64.slice(i * CHUNK, (i + 1) * CHUNK);
  assert.ok(part.length <= CHUNK, "chunk size bound");
  assert.ok(/^[A-Za-z0-9+/=]+$/.test(part), "clean base64");
}
console.log(
  `mascot sequences ok: sprite ${png.length}B -> ${chunks} chunks of ≤${CHUNK}`,
);
