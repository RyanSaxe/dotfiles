// The rail's one brain. Rail panes hold only `tail -f /dev/null`; this
// process renders every frame and writes it straight to each rail pane's
// tty. tmux interprets those writes into its own screen buffer, so frames
// survive detach/attach and remote clients with no viewer process at all.
//
// Cadence: tmux geometry/windows every 250ms, stretched to 2s while the
// rail is disabled or no client is attached (the enabled flag wakes it
// instantly); agents reconciled every 5s with instant refreshes when a
// workmux state file changes; palette re-read when the theme system
// rewrites it. Frames are diffed per pane — an unchanged rail costs zero
// writes.
//
// The daemon also enforces the rail's invariants every tick (self-heal):
// rails are exactly RAIL_WIDTH wide, hold no scrollback, are never in
// copy-mode, are never the selected pane, exist in every window while
// enabled (alt+g is the ONLY gate — no width policy), exist nowhere
// while disabled, and never survive alone in a window.

import { existsSync, readFileSync, watch } from "node:fs";
import { mkdir, readFile, unlink, writeFile } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";

import { loadAcks, updateAcks } from "./acks.js";
import {
  applyDoneHysteresis,
  collectAgents,
  collectSnapshot,
  run,
  tmux,
  windowsOf,
  type Agent,
  type Pane,
} from "./data.js";
import { assignHints, writeHints } from "./hints.js";
import { publishAttention, pushPhone } from "./notifications.js";
import { XDG_STATE } from "./paths.js";
import { mascotFor } from "./mascot.js";
import { GUTTER_COLS, renderRail } from "./render.js";
import { spriteId, transmitSprite, writeTty } from "./sprite.js";
import { loadPalette, railBg } from "./theme.js";

const TICK_MS = 250;
// With the rail disabled or no client attached, nothing on screen can
// change: stretch the cadence so the steady state costs ~nothing. The
// enabled-flag watch in main() cuts an idle sleep short, so `rail on`
// still lands within a tick.
const IDLE_TICK_MS = 2000;
const AGENT_RECONCILE_TICKS = 20; // every 5s
// 22 content cells (~211pt at font-size 16, the verdicted rail width)
// plus the crust gutter renderRail appends.
const RAIL_WIDTH = 22 + GUTTER_COLS;
// Split feasibility, not policy: below this tmux can't fit rail + border
// + any content. Visibility is controlled by alt+g alone.
const MIN_SPLIT_WIDTH = RAIL_WIDTH + 2;

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
let appliedBg = "";
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
  // The pane's DEFAULT background must match the frames: tmux clears a
  // pane region to its default bg before redrawing on window/session
  // switches, and a default that differs from the rail's crust flashes
  // visibly on every switch. (Content panes don't need this — their bg
  // already equals the terminal default.)
  await tmux("select-pane", "-P", `bg=${railBg(loadPalette())}`, "-t", paneId);
  // No per-pane border styling: borders are crust-filled globally
  // (tmux.conf), which is attribution-proof — per-pane styles only ever
  // controlled half a shared border and the active pane's style took
  // the rest.
  await tmux("select-pane", "-d", "-t", paneId);
}

// Enforce every rail invariant against one snapshot. Any pane this touched
// is skipped for painting this tick — it repaints next tick at its
// corrected geometry.
async function selfHeal(panes: Pane[], enabled: boolean): Promise<Set<string>> {
  const touched = new Set<string>();

  // Disabled means NO rail panes anywhere, and the daemon owns that
  // invariant: the launcher's kill sweep can race a tick that spawned a
  // rail after the sweep listed panes, and a stray @rail pane planted
  // any other way would otherwise be adopted and painted forever. The
  // other heals are moot for panes being removed.
  if (!enabled) {
    for (const pane of panes) {
      if (!pane.isRail) continue;
      // A rail alone in its window would leave an empty window behind.
      await (
        pane.windowPanes === 1
          ? tmux("kill-window", "-t", pane.windowId)
          : tmux("kill-pane", "-t", pane.paneId)
      ).catch(() => {});
      touched.add(pane.paneId);
    }
    return touched;
  }

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
    // tmux resizes panes proportionally on window resize; the rail's width
    // is not negotiable. A resize REFLOWS whatever was on screen (old
    // frames wrap line by line), and that can corrupt the display without
    // raising history — so a resize always drops the pushed cache and the
    // scrollback, forcing a clean repaint next tick.
    if (pane.width !== RAIL_WIDTH) {
      await tmux(
        "resize-pane",
        "-t",
        pane.paneId,
        "-x",
        String(RAIL_WIDTH),
      ).catch(() => {});
      await tmux("clear-history", "-t", pane.paneId).catch(() => {});
      pushed.delete(pane.paneId);
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

  // While enabled, EVERY window grows a rail — no width policy, alt+g is
  // the only gate. This reconcile makes it inevitable.
  const seen = new Set<string>();
  for (const pane of panes) {
    if (seen.has(pane.windowId) || pane.isRail) continue;
    seen.add(pane.windowId);
    if (
      pane.windowWidth >= MIN_SPLIT_WIDTH &&
      !railByWindow.has(pane.windowId)
    ) {
      await spawnRail(pane.windowId).catch(() => {});
    }
  }
  return touched;
}

// Auto separators: a window's crust hairlines show only with 2+ content
// panes (@wborders read by the border styles at draw time). Hooks flip
// the flag instantly; this reconcile makes it inevitable (break-pane,
// join-pane — anything hookless). Only mismatches cost a tmux call.
const windowBorders = new Map<string, boolean>();

async function reconcileWindowBorders(panes: Pane[]): Promise<void> {
  const counts = new Map<string, number>();
  for (const pane of panes) {
    if (pane.isRail) continue;
    counts.set(pane.windowId, (counts.get(pane.windowId) ?? 0) + 1);
  }
  const seen = new Set<string>();
  for (const pane of panes) {
    if (seen.has(pane.windowId)) continue;
    seen.add(pane.windowId);
    const want = (counts.get(pane.windowId) ?? 0) >= 2;
    if (windowBorders.get(pane.windowId) === want) continue;
    windowBorders.set(pane.windowId, want);
    const args = want
      ? ["set-option", "-w", "-t", pane.windowId, "@wborders", "1"]
      : ["set-option", "-w", "-t", pane.windowId, "-u", "@wborders"];
    await tmux(...args).catch(() => {});
  }
  for (const windowId of windowBorders.keys()) {
    if (!seen.has(windowId)) windowBorders.delete(windowId);
  }
}

// Mascot cells ride two gates. A terminal without kitty graphics cannot
// even LAY OUT the placeholder text (astral codepoint plus combining
// diacritics desync its column accounting and garble the pane), so a
// frame carries the mascot only while the driving client is capable AND
// no non-kitty client is viewing that session — frames live in tmux's
// buffers, and a per-session leak paints garbage on whichever phone
// client attaches next. Capability flips repaint within a tick.

// Terminals drop image data on restart and the daemon can't observe that;
// a slow re-send through each visible rail pane keeps sprites alive. The
// key includes the id so an id change (camouflage follows the theme
// background) retransmits immediately instead of waiting out the timer.
const TRANSMIT_INTERVAL_MS = 60_000;
const lastTransmit = new Map<string, number>();

function maybeTransmit(pane: Pane, spritePath: string, id: number): void {
  const key = `${pane.paneId}\x1f${spritePath}\x1f${id}`;
  const last = lastTransmit.get(key) ?? 0;
  if (Date.now() - last < TRANSMIT_INTERVAL_MS) return;
  if (transmitSprite(pane.tty, spritePath, id)) {
    lastTransmit.set(key, Date.now());
    // Repaint after the data lands so the placeholder cells composite.
    pushed.delete(pane.paneId);
  }
}

// Returns whether the daemon may idle until the next tick.
async function tick(counter: number): Promise<boolean> {
  const refresh =
    counter % AGENT_RECONCILE_TICKS === 0 || !agentsFresh
      ? refreshAgents().then(() => {
          agentsFresh = true;
        })
      : Promise.resolve();
  // The tmux poll and the agent refresh are independent — one round-trip
  // of latency, not two.
  const [{ panes, clientFacts }] = await Promise.all([
    collectSnapshot(),
    refresh,
  ]);
  const { modeSessions, nonKittySessions } = clientFacts;
  const palette = loadPalette();
  // Keep every rail pane's default bg in step with the theme (spawn sets
  // it once; a mode flip changes crust under all existing panes).
  const bg = railBg(palette);
  if (bg !== appliedBg) {
    for (const pane of panes) {
      if (!pane.isRail) continue;
      await tmux("select-pane", "-P", `bg=${bg}`, "-t", pane.paneId).catch(
        () => {},
      );
    }
    appliedBg = bg;
  }
  const enabled = existsSync(ENABLED_FLAG);
  const skip = await selfHeal(panes, enabled);
  await reconcileWindowBorders(panes);

  const settled = applyDoneHysteresis(agents, Date.now() / 1000);
  const acked = updateAcks(acks, settled, panes);
  const sessions = new Set(panes.map((pane) => pane.session));
  const hintsBySession = assignHints(settled, sessions, acked);
  writeHints(settled, hintsBySession, acked);
  publishAttention(settled, acked);
  pushPhone(settled, panes);

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
    // Each session's rail wears its own mascot accent: the identity
    // follows the project mapping, not the globally active theme accent.
    const mascot = mascotFor(pane.session);
    const accent =
      (palette.mode === "dark" ? mascot?.accentDark : mascot?.accentLight) ??
      palette.accent;
    const sessionPalette = { ...palette, accent };
    const spritePath =
      clientFacts.latestClientIsKitty && !nonKittySessions.has(pane.session)
        ? (mascot?.spritePath ?? null)
        : null;
    const sprite = spritePath ? spriteId(spritePath, railBg(palette)) : null;
    const prefixHeld = modeSessions.has(pane.session);
    const bucket = `${pane.session}\x1f${pane.width}\x1f${pane.height}\x1f${sprite}\x1f${page}\x1f${prefixHeld}`;
    let frame = frames.get(bucket);
    if (frame === undefined) {
      const data = {
        session: pane.session,
        windows: windowsOf(panes, pane.session),
        agents: settled,
        acked,
        hints: hintsBySession.get(pane.session) ?? new Map<string, string>(),
        sprite,
        page,
        prefixHeld,
      };
      frame = toFrame(
        renderRail(data, sessionPalette, pane.width, pane.height),
      );
      frames.set(bucket, frame);
    }
    // Transmission additionally needs a VISIBLE pane — tmux only forwards
    // passthrough for panes on screen. Kitty terminals retain previously
    // loaded images, so mascots persist through a transmit pause and
    // resume on detach.
    if (
      spritePath &&
      sprite !== null &&
      pane.sessionAttached &&
      pane.windowActive
    ) {
      maybeTransmit(pane, spritePath, sprite);
    }
    paintPane(pane, frame);
  }

  // Forget panes that no longer exist so their ids can't shadow reused ones.
  const alive = new Set(panes.map((pane) => pane.paneId));
  for (const paneId of pushed.keys()) {
    if (!alive.has(paneId)) pushed.delete(paneId);
  }

  return !enabled || clientFacts.clientCount === 0;
}

// An interruptible sleep: the enabled-flag watch calls wakeLoop so
// `rail on` never waits out an idle interval.
let wakeLoop: () => void = () => {};

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => {
    const timer = setTimeout(finish, ms);
    function finish(): void {
      clearTimeout(timer);
      wakeLoop = () => {};
      resolve();
    }
    wakeLoop = finish;
  });
}

// Exclusive-create (wx) makes the pidfile the lock itself: two daemons
// booting concurrently — npx tsx takes ~1s to get here, and tmux.conf
// sourcing races `rail on` — can both pass a check-then-write gate, but
// only one wins the create. A dead holder's file is unlinked and the
// claim retried; the loop is bounded for the pathological case where
// fresh claimants keep dying mid-race.
async function claimPidfile(): Promise<boolean> {
  for (let attempt = 0; attempt < 5; attempt++) {
    try {
      await writeFile(PID_FILE, String(process.pid), { flag: "wx" });
      return true;
    } catch {
      // Pidfile exists; reclaim below only if its holder is dead.
    }
    try {
      const pid = Number(await readFile(PID_FILE, "utf8"));
      if (pid > 0) {
        process.kill(pid, 0);
        return false;
      }
    } catch {
      // Unreadable pidfile or dead holder: stale.
    }
    await unlink(PID_FILE).catch(() => {});
  }
  return false;
}

async function main(): Promise<void> {
  await mkdir(STATE_DIR, { recursive: true });
  if (!(await claimPidfile())) {
    console.error("rail daemon already running");
    process.exit(0);
  }

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
  // Theme/mascot switches rewrite the generated files: drop frame caches
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

  watch(STATE_DIR, (_event, filename) => {
    if (filename === "enabled") wakeLoop();
  });

  let counter = 0;
  for (;;) {
    const started = Date.now();
    let idle = false;
    try {
      idle = await tick(counter);
    } catch (error) {
      // tmux server gone (or restarting): keep the daemon alive and poll
      // gently until it returns.
      console.error(`tick failed: ${String(error)}`);
      await new Promise((resolve) => setTimeout(resolve, 2000));
    }
    counter += 1;
    const elapsed = Date.now() - started;
    const cadence = idle ? IDLE_TICK_MS : TICK_MS;
    await sleep(Math.max(0, cadence - elapsed));
  }
}

await main();
