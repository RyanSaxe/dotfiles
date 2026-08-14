// The rail's one brain. Rail panes hold only `tail -f /dev/null`; this
// process renders every frame and writes it straight to each rail pane's
// tty. tmux interprets those writes into its own screen buffer, so frames
// survive detach/attach and remote clients with no viewer process at all.
//
// Cadence: tmux geometry/windows every 250ms; agents reconciled every 5s
// with instant refreshes when a workmux state file changes; palette re-read
// when the theme system rewrites it. Frames are diffed per pane — an
// unchanged rail costs zero writes.
//
// The daemon also enforces the rail's invariants every tick (self-heal):
// rails are exactly RAIL_WIDTH wide, hold no scrollback, are never in
// copy-mode, are never the selected pane, don't exist in narrow windows,
// exist in wide ones while enabled, and never survive alone in a window.

import { existsSync, readFileSync, watch } from "node:fs";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";

import { loadAcks, updateAcks } from "./acks.js";
import {
  applyDoneHysteresis,
  collectAgents,
  collectPanes,
  run,
  tmux,
  windowsOf,
  type Agent,
  type Pane,
} from "./data.js";
import { assignHints, writeHints } from "./hints.js";
import { XDG_STATE } from "./paths.js";
import { pokemonFor } from "./pokemon.js";
import { GUTTER_COLS, renderRail } from "./render.js";
import { spriteId, transmitSprite, writeTty } from "./sprite.js";
import { loadPalette } from "./theme.js";

const TICK_MS = 250;
const AGENT_RECONCILE_TICKS = 20; // every 5s
// 22 content cells (~211pt at font-size 16, the verdicted rail width)
// plus the crust gutter renderRail appends.
const RAIL_WIDTH = 22 + GUTTER_COLS;
// Hysteresis: rails die below 100 but only spawn above 110, so a window
// hovering at the boundary can't flap between the two.
const KILL_BELOW_WIDTH = 100;
const SPAWN_ABOVE_WIDTH = 110;

const STATE_DIR = join(XDG_STATE, "dotfiles/rail");
const PID_FILE = join(STATE_DIR, "daemon.pid");
const ENABLED_FLAG = join(STATE_DIR, "enabled");
const PAGE_FILE = join(STATE_DIR, "page");
// workmux manages its own state home; not ours to redirect via XDG.
const WORKMUX_STATE = join(homedir(), ".local/state/workmux");
const GENERATED_DIR = join(XDG_STATE, "dotfiles/generated");
const THEME_SYNC = join(homedir(), ".config/tmux/scripts/theme-sync.sh");

const HIDE_CURSOR = "\x1b[?25l";
const SYNC_ON = "\x1b[?2026h";
const SYNC_OFF = "\x1b[?2026l";

let agents: Agent[] = [];
let agentsFresh = false;
const acks = loadAcks();
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
  if (writeTty(pane.tty, SYNC_ON + HIDE_CURSOR + frame + SYNC_OFF)) {
    pushed.set(pane.paneId, frame);
  }
}

function toFrame(lines: string[]): string {
  return lines.map((text, row) => `\x1b[${row + 1};1H${text}`).join("");
}

async function spawnRail(windowId: string): Promise<void> {
  const { stdout } = await tmux(
    "split-window",
    "-hbf",
    "-d",
    "-l",
    String(RAIL_WIDTH),
    "-t",
    windowId,
    "-P",
    "-F",
    "#{pane_id}",
    "tail -f /dev/null",
  );
  const paneId = stdout.trim();
  await tmux("set-option", "-p", "-t", paneId, "@rail", "1");
  // The rail's own border hides (per-pane style wins the shared border):
  // the seam stays a pure color boundary while content-content splits
  // keep the global separator line.
  await tmux(
    "set-option",
    "-p",
    "-t",
    paneId,
    "pane-border-style",
    "fg=#{@bg}",
  );
  await tmux("select-pane", "-d", "-t", paneId);
}

// Enforce every rail invariant against one snapshot. Any pane this touched
// is skipped for painting this tick — it repaints next tick at its
// corrected geometry.
async function selfHeal(panes: Pane[]): Promise<Set<string>> {
  const touched = new Set<string>();
  const enabled = existsSync(ENABLED_FLAG);
  const railByWindow = new Map<string, Pane>();
  for (const pane of panes) {
    if (!pane.isRail) continue;
    const first = railByWindow.get(pane.windowId);
    if (first === undefined) {
      railByWindow.set(pane.windowId, pane);
    } else {
      // One rail per window, no exceptions — a duplicate (however it was
      // born) dies on sight.
      await tmux("kill-pane", "-t", pane.paneId).catch(() => {});
      touched.add(pane.paneId);
    }
  }

  for (const pane of panes) {
    if (!pane.isRail || touched.has(pane.paneId)) continue;

    // A rail alone in a window is a zombie: every content pane is gone.
    if (pane.windowPanes === 1) {
      await tmux("kill-window", "-t", pane.windowId).catch(() => {});
      touched.add(pane.paneId);
      continue;
    }
    // Narrow windows carry no rail; the content pane wins.
    if (pane.windowWidth < KILL_BELOW_WIDTH) {
      await tmux("kill-pane", "-t", pane.paneId).catch(() => {});
      touched.add(pane.paneId);
      continue;
    }
    // tmux resizes panes proportionally on window resize; the rail's width
    // is not negotiable.
    if (pane.width !== RAIL_WIDTH) {
      await tmux(
        "resize-pane",
        "-t",
        pane.paneId,
        "-x",
        String(RAIL_WIDTH),
      ).catch(() => {});
      touched.add(pane.paneId);
    }
    // NO SCROLLING, ever: any scrollback means a write raced a resize —
    // drop the history and force a clean repaint.
    if (pane.historySize > 0) {
      await tmux("clear-history", "-t", pane.paneId).catch(() => {});
      pushed.delete(pane.paneId);
      touched.add(pane.paneId);
    }
    // Copy-mode on a rail (mouse wheel, stray bind) shows [0/0]; cancel it.
    if (pane.inMode) {
      await tmux("send-keys", "-X", "-t", pane.paneId, "cancel").catch(
        () => {},
      );
      touched.add(pane.paneId);
    }
    // The rail is display-only: selection bounces to a content pane.
    if (pane.paneActive) {
      const sibling = panes.find(
        (candidate) =>
          candidate.windowId === pane.windowId && !candidate.isRail,
      );
      if (sibling) {
        await tmux("select-pane", "-t", sibling.paneId).catch(() => {});
      }
    }
  }

  // While enabled, every wide-enough window grows a rail — hooks make this
  // instant, this reconcile makes it inevitable.
  if (enabled) {
    const seen = new Set<string>();
    for (const pane of panes) {
      if (seen.has(pane.windowId) || pane.isRail) continue;
      seen.add(pane.windowId);
      if (
        pane.windowWidth >= SPAWN_ABOVE_WIDTH &&
        !railByWindow.has(pane.windowId)
      ) {
        await spawnRail(pane.windowId).catch(() => {});
      }
    }
  }
  return touched;
}

// Sprites render only for sessions where EVERY attached client identifies
// as a kitty-graphics terminal — the daemon can't see through tmux to the
// outer terminal any other way, and emitting graphics at an incapable
// client (a phone, a plain SSH terminal) shows up as garbage. tmux's own
// client table is the source of truth, re-read every tick.
async function capableSessions(): Promise<Set<string>> {
  const capable = new Set<string>();
  const incapable = new Set<string>();
  const { stdout } = await tmux(
    "list-clients",
    "-F",
    "#{client_session}\x1f#{client_termname}",
  );
  for (const clientLine of stdout.split("\n")) {
    if (!clientLine) continue;
    const [session, termname] = clientLine.split("\x1f");
    if (!session) continue;
    if (/ghostty|kitty/i.test(termname ?? "")) {
      capable.add(session);
    } else {
      incapable.add(session);
    }
  }
  for (const session of incapable) capable.delete(session);
  return capable;
}

// Terminals drop image data on restart and the daemon can't observe that;
// a slow re-send through each visible rail pane keeps sprites alive.
const TRANSMIT_INTERVAL_MS = 60_000;
const lastTransmit = new Map<string, number>();

function maybeTransmit(pane: Pane, spritePath: string): void {
  const key = `${pane.paneId}\x1f${spritePath}`;
  const last = lastTransmit.get(key) ?? 0;
  if (Date.now() - last < TRANSMIT_INTERVAL_MS) return;
  if (transmitSprite(pane.tty, spritePath)) {
    lastTransmit.set(key, Date.now());
    // Repaint after the data lands so the placeholder cells composite.
    pushed.delete(pane.paneId);
  }
}

async function tick(counter: number): Promise<void> {
  const refresh =
    counter % AGENT_RECONCILE_TICKS === 0 || !agentsFresh
      ? refreshAgents().then(() => {
          agentsFresh = true;
        })
      : Promise.resolve();
  // The polls are independent — one round-trip of latency, not three.
  const [panes, spriteCapable] = await Promise.all([
    collectPanes(),
    capableSessions(),
    refresh,
  ]);
  const palette = loadPalette();
  const skip = await selfHeal(panes);

  const settled = applyDoneHysteresis(agents, Date.now() / 1000);
  const acked = updateAcks(acks, settled, panes);
  const hints = assignHints(settled);
  writeHints(settled, hints);

  // Pagination state, written by `rail page up|down`; the renderer clamps.
  let page = 0;
  try {
    page = Math.max(0, Number(readFileSync(PAGE_FILE, "utf8")) || 0);
  } catch {
    // No page file: top of the list.
  }

  const frames = new Map<string, string>();
  for (const pane of panes) {
    if (!pane.isRail || skip.has(pane.paneId)) continue;
    // Each session's rail wears its own pokemon accent: the identity
    // follows the project mapping, not the globally active theme accent.
    const pokemon = pokemonFor(pane.session);
    const accent =
      (palette.mode === "dark" ? pokemon?.accentDark : pokemon?.accentLight) ??
      palette.accent;
    const sessionPalette = { ...palette, accent };
    const spritePath =
      spriteCapable.has(pane.session) && pokemon?.spritePath
        ? pokemon.spritePath
        : null;
    const sprite = spritePath ? spriteId(spritePath) : null;
    const bucket = `${pane.session}\x1f${pane.width}\x1f${pane.height}\x1f${sprite}\x1f${page}`;
    let frame = frames.get(bucket);
    if (frame === undefined) {
      const data = {
        session: pane.session,
        windows: windowsOf(panes, pane.session),
        agents: settled,
        acked,
        hints,
        sprite,
        page,
      };
      frame = toFrame(
        renderRail(data, sessionPalette, pane.width, pane.height),
      );
      frames.set(bucket, frame);
    }
    if (spritePath && pane.sessionAttached && pane.windowActive) {
      maybeTransmit(pane, spritePath);
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
  // Theme/pokemon switches rewrite the generated files: drop frame caches
  // so every pane repaints, and re-source tmux's own colors (this replaces
  // the statusline's theme-sync slot — the statusline is off while the
  // rail carries the chrome). A render touches every template output in a
  // burst; debounce so the burst costs one pass, not one per file event.
  let themePending: NodeJS.Timeout | null = null;
  let tuisColorsTouched = false;
  watch(GENERATED_DIR, (_event, filename) => {
    if (filename === "tuis-colors.json") tuisColorsTouched = true;
    if (themePending) clearTimeout(themePending);
    themePending = setTimeout(() => {
      if (tuisColorsTouched) pushed.clear();
      tuisColorsTouched = false;
      run(THEME_SYNC, []).catch(() => {});
    }, 30);
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
