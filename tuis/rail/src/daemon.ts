// The rail's one brain. Rail panes hold only `tail -f /dev/null`; this
// process renders every frame and writes it straight to each rail pane's
// tty. tmux interprets those writes into its own screen buffer, so frames
// survive detach/attach and remote clients with no viewer process at all.
//
// Cadence: tmux geometry/windows every 250ms; agents reconciled every 5s
// with instant refreshes when a workmux state file changes; palette re-read
// when the theme system rewrites it. Frames are diffed per pane — an
// unchanged rail costs zero writes.

import { watch } from "node:fs";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { closeSync, openSync, writeSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { execFile } from "node:child_process";
import { promisify } from "node:util";

import {
  collectAgents,
  collectPanes,
  windowsOf,
  type Agent,
  type Pane,
} from "./data.js";
import { renderRail } from "./render.js";
import { loadPalette } from "./theme.js";

const run = promisify(execFile);

const TICK_MS = 250;
const AGENT_RECONCILE_TICKS = 20; // every 5s
const STATE_DIR = join(
  process.env.XDG_STATE_HOME ?? join(homedir(), ".local/state"),
  "dotfiles/rail",
);
const PID_FILE = join(STATE_DIR, "daemon.pid");
const WORKMUX_STATE = join(homedir(), ".local/state/workmux");
const GENERATED_DIR = join(
  process.env.XDG_STATE_HOME ?? join(homedir(), ".local/state"),
  "dotfiles/generated",
);

const HIDE_CURSOR = "\x1b[?25l";
const SYNC_ON = "\x1b[?2026h";
const SYNC_OFF = "\x1b[?2026l";

let agents: Agent[] = [];
let agentsFresh = false;
// Last frame written per pane id — the no-flicker, no-waste diff.
const pushed = new Map<string, string>();

async function refreshAgents(): Promise<void> {
  try {
    agents = await collectAgents();
  } catch {
    // workmux missing or transient failure: keep the last known agents.
  }
}

function paintPane(pane: Pane, frame: string): void {
  if (pushed.get(pane.paneId) === frame) return;
  try {
    const fd = openSync(pane.tty, "w");
    writeSync(fd, SYNC_ON + HIDE_CURSOR + frame + SYNC_OFF);
    closeSync(fd);
    pushed.set(pane.paneId, frame);
  } catch {
    // The pane died between the poll and the write; the next tick forgets it.
  }
}

function toFrame(lines: string[]): string {
  return lines.map((text, row) => `\x1b[${row + 1};1H${text}`).join("");
}

async function killZombieWindows(panes: Pane[]): Promise<void> {
  for (const pane of panes) {
    if (pane.isRail && pane.windowPanes === 1) {
      // A rail alone in a window is a zombie: every content pane is gone.
      await run("tmux", ["kill-window", "-t", pane.windowId]).catch(() => {});
      pushed.delete(pane.paneId);
    }
  }
}

async function tick(counter: number): Promise<void> {
  if (counter % AGENT_RECONCILE_TICKS === 0 || !agentsFresh) {
    await refreshAgents();
    agentsFresh = true;
  }
  const panes = await collectPanes();
  await killZombieWindows(panes);

  const palette = loadPalette();
  const frames = new Map<string, string>();
  for (const pane of panes) {
    if (!pane.isRail || pane.windowPanes === 1) continue;
    const bucket = `${pane.session}\x1f${pane.width}\x1f${pane.height}`;
    let frame = frames.get(bucket);
    if (frame === undefined) {
      const data = {
        session: pane.session,
        windows: windowsOf(panes, pane.session),
        agents,
      };
      frame = toFrame(renderRail(data, palette, pane.width, pane.height));
      frames.set(bucket, frame);
    }
    paintPane(pane, frame);
  }

  // Forget panes that no longer exist so their ids can't shadow reused ones.
  const alive = new Set(panes.map((pane) => pane.paneId));
  for (const paneId of pushed.keys()) {
    if (!alive.has(paneId)) pushed.delete(paneId);
  }
}

async function alreadyRunning(): Promise<boolean> {
  try {
    const pid = Number(await readFile(PID_FILE, "utf8"));
    if (pid > 0) {
      process.kill(pid, 0);
      return true;
    }
  } catch {
    // No pidfile or stale pid: not running.
  }
  return false;
}

async function main(): Promise<void> {
  await mkdir(STATE_DIR, { recursive: true });
  if (await alreadyRunning()) {
    console.error("rail daemon already running");
    process.exit(0);
  }
  await writeFile(PID_FILE, String(process.pid));

  // Instant agent updates: workmux hooks write a state file the moment an
  // agent changes status. Debounced a hair so bursts coalesce.
  let pending: NodeJS.Timeout | null = null;
  try {
    watch(join(WORKMUX_STATE, "agents"), () => {
      if (pending) clearTimeout(pending);
      pending = setTimeout(() => {
        agentsFresh = false;
      }, 30);
    });
  } catch {
    // Directory appears with the first agent; the 5s reconcile covers it.
  }
  // Theme/pokemon switches rewrite the palette; drop frame caches so every
  // pane repaints in the new colors.
  watch(GENERATED_DIR, (_event, filename) => {
    if (filename === "tuis-colors.json") pushed.clear();
  });

  let counter = 0;
  for (;;) {
    const started = Date.now();
    try {
      await tick(counter);
    } catch (error) {
      // tmux server gone (or restarting): keep the daemon alive and poll
      // gently until it returns.
      console.error(`tick failed: ${String(error)}`);
      await new Promise((resolve) => setTimeout(resolve, 2000));
    }
    counter += 1;
    const elapsed = Date.now() - started;
    await new Promise((resolve) =>
      setTimeout(resolve, Math.max(0, TICK_MS - elapsed)),
    );
  }
}

await main();
