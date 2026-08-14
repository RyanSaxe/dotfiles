// Look-spike entry: render the rail for one session into the current
// terminal, refreshing on an interval. The daemon/viewer split arrives
// later; this process is the whole pipeline for judging the look.
//
//   RAIL_SESSION=dotfiles npx tsx src/app.ts

import { collect, currentSession } from "./data.js";
import { renderRail } from "./render.js";
import { loadPalette } from "./theme.js";

const REFRESH_MS = 500;

const ALT_SCREEN_ON = "\x1b[?1049h\x1b[?25l";
const ALT_SCREEN_OFF = "\x1b[?1049l\x1b[?25h";
// Synchronized output: the terminal commits the frame atomically — no
// half-painted rails, ever.
const SYNC_ON = "\x1b[?2026h";
const SYNC_OFF = "\x1b[?2026l";

let lastFrame = "";

function paint(lines: string[]): void {
  const frame = lines.map((text, row) => `\x1b[${row + 1};1H${text}`).join("");
  if (frame === lastFrame) return;
  lastFrame = frame;
  process.stdout.write(SYNC_ON + frame + SYNC_OFF);
}

async function tick(session: string): Promise<void> {
  const [data, palette] = [await collect(session), loadPalette()];
  const width = process.stdout.columns || 34;
  const height = process.stdout.rows || 40;
  paint(renderRail(data, palette, width, height));
}

function shutdown(): void {
  process.stdout.write(ALT_SCREEN_OFF);
  process.exit(0);
}

const session = process.env.RAIL_SESSION || (await currentSession());
process.stdout.write(ALT_SCREEN_ON);
process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);
// A resize instantly repaints at the new geometry.
process.stdout.on("resize", () => {
  lastFrame = "";
  void tick(session);
});

await tick(session);
setInterval(() => void tick(session), REFRESH_MS);
