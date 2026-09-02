// The rail's one brain. Rail panes hold only `tail -f /dev/null`; this
// process renders every frame and writes it straight to each rail pane's
// tty. tmux interprets those writes into its own screen buffer, so frames
// survive detach/attach and remote clients with no viewer process at all.
//
// Event-driven, not polled: a tmux control-mode client (src/control.ts)
// delivers structural notifications the moment anything changes, and
// every wake source — control events, state-file writes, theme output,
// poller changes — funnels into one refresh scheduler (src/scheduler.ts)
// that coalesces bursts and never drops a signal. Each refresh reads one
// tmux snapshot (over the control socket when up, exec otherwise), the
// slow sources' cached values (src/pollers.ts: workmux 5s, vault 5s on
// the Tasks tab / 60s elsewhere, host probes 5s), renders, and paints.
// A reconcile backstop requests a refresh every 2s (10s while disabled
// with no clients) so nothing observable ever depends on an event
// arriving. Frames are diffed per pane — an unchanged rail costs zero
// writes. RAIL_NO_CONTROL=1 disables the control client entirely; every
// snapshot then rides the exec fallback on the backstop cadence.
//
// The daemon also enforces the rail's invariants every refresh
// (self-heal): rails are exactly RAIL_WIDTH wide, hold no scrollback,
// are never in copy-mode, are never the selected pane, exist in every
// window while enabled (alt+g is the ONLY gate — no width policy), exist
// nowhere while disabled, and never survive alone in a window.

import { existsSync, readFileSync, watch } from "node:fs";
import { mkdir, readFile, unlink, writeFile } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";

import { loadAcks, updateAcks } from "./acks.js";
import { loadReviewSnapshot } from "./attention/review.js";
import { startControlClient, type ControlClient } from "./control.js";
import {
  collectAgents,
  collectClientFacts,
  clientModeSignature,
  collectSnapshot,
  run,
  stabilizeAgents,
  tmux,
  windowsOf,
  type Agent,
  type Pane,
  type SnapshotRunner,
} from "./data.js";
import { assignHints, writeHints } from "./hints.js";
import { logLine } from "./log.js";
import {
  publishAttention,
  publishReviewAttention,
  pushPhone,
} from "./notifications.js";
import { XDG_STATE } from "./paths.js";
import { makePoller, stateFileWake } from "./pollers.js";
import {
  collectHostFacts,
  isPresent,
  PRESENCE_IDLE_SECS,
  type HostFacts,
} from "./probes.js";
import { mascotFor } from "./mascot.js";
import { GUTTER_COLS, renderRail } from "./render.js";
import { makeRefreshScheduler } from "./scheduler.js";
import { fillOrder, makePaintScheduler } from "./paint.js";
import { spriteId, transmitSprite, writeTtyAsync } from "./sprite.js";
import {
  loadStableStatuses,
  saveStableStatuses,
  stableStatusesKey,
} from "./stability.js";
import { loadRailTab } from "./tabs.js";
import {
  emptyTaskSnapshot,
  loadTaskSnapshot,
  type TaskSnapshot,
} from "./tasks.js";
import {
  countPaint,
  countPanePainted,
  dump,
  recordRefresh,
  timed,
} from "./telemetry.js";
import { loadPalette, railBg } from "./theme.js";

// Refresh scheduling: a burst of wake signals coalesces into one refresh
// 25ms after it began; a sustained storm is capped at one per 50ms.
const COALESCE_MS = 25;
const MIN_REFRESH_INTERVAL_MS = 50;
// The reconcile backstop: the only recurring wake. It bounds the damage
// of any missed event (a window created while the control client was
// reconnecting, a blocked tty retry) at 2s — today's idle cadence — and
// stretches to 10s while the rail is disabled AND no client is attached,
// when nothing on screen can change.
const RECONCILE_MS = 2000;
const IDLE_RECONCILE_MS = 10_000;
// Slow-source cadences. workmux's watcher trigger floor keeps agent
// state churn (heartbeat rewrites) from turning the 5s poll into a storm.
const WORKMUX_POLL_MS = 5000;
const WORKMUX_TRIGGER_GAP_MS = 1000;
// `vault tasks --json` re-walks the vault on every call, so the Tasks
// tab gets the live cadence and every other tab a slow pulse — enough to
// keep the tab's own overdue signal honest while you look elsewhere.
// Switching TO the tasks tab triggers an early read (the visit is what
// makes the list current).
const VAULT_TASKS_POLL_MS = 5000;
const VAULT_IDLE_POLL_MS = 60_000;
const HOST_POLL_MS = 5000;
// Matches the old tick cadence: a held prefix feels instant. Cheap —
// one list-clients, and it renders only when the projection changes.
const CLIENT_POLL_MS = 250;
// tmux's two dead-server voices, appended to the exec error via stderr.
const NO_SERVER_PATTERN = /no server running|error connecting/i;
// Exec-fallback dead-server detection (the control client has its own
// ~10s ladder): failed refreshes retry on the 2s reconcile, so five
// consecutive no-server failures ≈ 10s — enough to ride out a server
// restart, short enough that a dead server doesn't leave the daemon
// erroring forever.
const NO_SERVER_EXIT_FAILS = 5;
// 28 content cells: five terminal columns wider than the original rail,
// approximately 41px at the current font, plus the crust gutter. The tab
// bar derives chip positions from the registry, distributing spare cells
// between the chips when the labels or tab count change.
//
// 28 rather than 27 because the distribution can only come out even when
// the spare cells divide by the number of gaps. Today's three chips occupy
// 24 cells, so an even content width gives 2 and 2 while an odd one gives
// 2 and 1 — visibly off-centre, which is what 27 shipped as.
const RAIL_WIDTH = 28 + GUTTER_COLS;
// Split feasibility, not policy: below this tmux can't fit rail + border
// + any content. Visibility is controlled by alt+g alone.
const MIN_SPLIT_WIDTH = RAIL_WIDTH + 2;

const STATE_DIR = join(XDG_STATE, "dotfiles/rail");
const PID_FILE = join(STATE_DIR, "daemon.pid");
const ENABLED_FLAG = join(STATE_DIR, "enabled");
const PAGE_FILE = join(STATE_DIR, "page");
// workmux manages its own state home; not ours to redirect via XDG.
const WORKMUX_STATE = join(homedir(), ".local/state/workmux");
const ATTENTION_STATE_DIR = join(XDG_STATE, "dotfiles/attention");
const GENERATED_DIR = join(XDG_STATE, "dotfiles/generated");
const THEME_SYNC = join(homedir(), ".config/tmux/scripts/theme-sync.sh");

const HIDE_CURSOR = "\x1b[?25l";
const SYNC_ON = "\x1b[?2026h";
const SYNC_OFF = "\x1b[?2026l";

let appliedBg = "";
let warnedNoPalette = false;
const acks = loadAcks();
const stableStatuses = loadStableStatuses();
let stableStatusesDirty = false;
// Last frame written per pane id — the no-flicker, no-waste diff.
const pushed = new Map<string, string>();

// Visible rails paint before the refresh returns; the rest fill in the
// background, latest-frame-wins (src/paint.ts). `pushed` tracks the last
// COMPLETED write per pane — a rare revert-while-filling can briefly show
// a superseded frame, and the reconcile backstop repaints it within 2s.
const painter = makePaintScheduler({
  write: writeTtyAsync,
  onResult(paneId, frame, ok) {
    if (ok) {
      pushed.set(paneId, frame);
      countPanePainted();
    } else {
      // A failed write leaves the pane's contents unknown (a wedged pty
      // may have taken a partial frame): forget the cache so the next
      // refresh always retries instead of assuming this frame landed.
      pushed.delete(paneId);
    }
  },
});

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
// is skipped for painting this refresh — it repaints next refresh at its
// corrected geometry.
async function selfHeal(panes: Pane[], enabled: boolean): Promise<Set<string>> {
  const touched = new Set<string>();

  // Disabled means NO rail panes anywhere, and the daemon owns that
  // invariant: the launcher's kill sweep can race a refresh that spawned
  // a rail after the sweep listed panes, and a stray @rail pane planted
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
    // scrollback, forcing a clean repaint next refresh.
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

// Mascot cells ride two gates. A terminal without kitty graphics cannot
// even LAY OUT the placeholder text (astral codepoint plus combining
// diacritics desync its column accounting and garble the pane), so a
// frame carries the mascot only while the driving client is capable AND
// no non-kitty client is viewing that session — frames live in tmux's
// buffers, and a per-session leak paints garbage on whichever phone
// client attaches next. Capability flips repaint within a refresh.

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

// ----- wake plumbing -----------------------------------------------------

const CONTROL_DISABLED = process.env.RAIL_NO_CONTROL === "1";

// Control-mode notifications after which something the rail renders (or
// self-heals) may have changed. They are wake signals only — the
// snapshot read stays the source of truth, which is why the whole
// structural family maps to the same request.
const CONTROL_REFRESH_EVENTS: ReadonlySet<string> = new Set([
  "%client-attached",
  "%client-detached",
  "%client-session-changed",
  "%layout-change",
  "%pane-mode-changed",
  "%session-changed",
  "%session-renamed",
  "%session-window-changed",
  "%sessions-changed",
  "%unlinked-window-add",
  "%unlinked-window-close",
  "%unlinked-window-renamed",
  "%window-add",
  "%window-close",
  "%window-pane-changed",
  "%window-renamed",
]);
// Expected chatter with nothing to repaint. (%exit never arrives here —
// the control client consumes it as a disconnect.)
const CONTROL_IGNORED_EVENTS: ReadonlySet<string> = new Set([
  "%config-error",
  "%continue",
  "%extended-output",
  "%message",
  "%output",
  "%paste-buffer-changed",
  "%paste-buffer-deleted",
  "%pause",
  "%subscription-changed",
]);
const unknownControlEvents = new Set<string>();

let control: ControlClient | null = null;
let controlUp = false;

function controlRunner(): SnapshotRunner | undefined {
  if (control === null || !controlUp) return undefined;
  const client = control;
  return (commandLine) => client.command(commandLine);
}

async function exitServerGone(): Promise<void> {
  logLine("tmux server gone; exiting");
  await unlink(PID_FILE).catch(() => {});
  process.exit(0);
}

// ----- refresh -----------------------------------------------------------

let refreshCounter = 0;
let noServerFails = 0;
// Backstop cadence inputs, updated by every completed refresh.
let lastEnabled = true;
let lastClientCount = 1;

const scheduler = makeRefreshScheduler(guardedRefresh, {
  coalesceMs: COALESCE_MS,
  minIntervalMs: MIN_REFRESH_INTERVAL_MS,
  // Held until main() has loaded every slow source once — see the resume
  // after the boot request. Without this, the control client connecting
  // mid-startup fires a refresh over empty agents that wipes acks and
  // stability and replays phone pings.
  startPaused: true,
});

// Slow sources own their own wall-clock cadence; refreshes read the
// cached values and never wait on an exec. Change detection compares
// CONTENT (not file mtimes or object identity), so workmux heartbeat
// rewrites and byte-identical vault reads wake nothing.
function agentsKey(agents: Agent[]): string {
  return JSON.stringify(
    agents
      .map((agent) => [
        agent.paneId,
        agent.status,
        agent.statusTs,
        agent.title,
        agent.windowName,
      ])
      .sort(),
  );
}

const workmuxPoller = makePoller<Agent[]>({
  name: "workmux",
  intervalMs: () => WORKMUX_POLL_MS,
  load: () => timed("workmux", collectAgents()),
  changed: (previous, next) => agentsKey(previous) !== agentsKey(next),
  onChange: () => scheduler.request("workmux"),
});

const vaultPoller = makePoller<TaskSnapshot>({
  name: "vault",
  intervalMs: () =>
    loadRailTab() === "tasks" ? VAULT_TASKS_POLL_MS : VAULT_IDLE_POLL_MS,
  load: () => timed("vault", loadTaskSnapshot()),
  changed: (previous, next) =>
    JSON.stringify(previous) !== JSON.stringify(next),
  onChange: () => scheduler.request("vault"),
});

// Presence is the only host fact anything renders or routes on; probing
// is cheap and cached (probes.ts), so only the flip wakes a refresh.
function presenceOf(facts: HostFacts): boolean | null {
  return facts.inputIdleSecs === null
    ? null
    : facts.inputIdleSecs < PRESENCE_IDLE_SECS;
}

const hostPoller = makePoller<HostFacts>({
  name: "ioreg",
  intervalMs: () => HOST_POLL_MS,
  load: () => timed("ioreg", collectHostFacts()),
  changed: (previous, next) => presenceOf(previous) !== presenceOf(next),
  onChange: () => scheduler.request("presence"),
});

// prefix-held, the tab key-table, and client focus are the live bits the
// control protocol never announces. A lone list-clients (cheap: no pane
// walk) polls just those; a refresh fires only when the projection
// actually changes, so a held prefix repaints within a poll instead of
// waiting out the 2s reconcile, while steady state costs one list-clients
// and zero renders.
const clientPoller = makePoller<string>({
  name: "client",
  intervalMs: () => CLIENT_POLL_MS,
  load: () =>
    timed("client", collectClientFacts(controlRunner())).then(
      clientModeSignature,
    ),
  changed: (previous, next) => previous !== next,
  onChange: () => scheduler.request("client"),
});

// The refresh body, reading the pollers' caches: one snapshot, one heal,
// one render pass. Every wake source funnels here through the scheduler.
async function refreshAndRender(): Promise<void> {
  const started = Date.now();
  const activeTab = loadRailTab();
  const agents = workmuxPoller.value() ?? [];
  const taskSnapshot = vaultPoller.value() ?? emptyTaskSnapshot();
  const hostFacts = hostPoller.value() ?? { inputIdleSecs: null };
  const { panes, clientFacts } = await timed(
    "snapshot",
    collectSnapshot(controlRunner()),
  );
  const { modeSessions, nonKittySessions } = clientFacts;
  // Every frame is a color: with no rendered theme there is nothing sane to
  // paint, and rethrowing per refresh would spin forever with no
  // explanation. The generated-dir watch repaints everything the moment it
  // lands.
  let palette;
  try {
    palette = loadPalette();
  } catch {
    if (!warnedNoPalette) {
      warnedNoPalette = true;
      logLine("no palette yet; run `theme apply`. Rails stay unpainted");
    }
    return;
  }
  warnedNoPalette = false;
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
  const skip = await timed("selfHeal", selfHeal(panes, enabled));

  const stableBefore = stableStatusesKey(stableStatuses);
  const settled = stabilizeAgents(agents, stableStatuses, Date.now() / 1000);
  if (stableStatusesKey(stableStatuses) !== stableBefore) {
    stableStatusesDirty = true;
  }
  if (stableStatusesDirty) {
    try {
      saveStableStatuses(stableStatuses);
      stableStatusesDirty = false;
    } catch (error) {
      logLine(`status stability persistence failed: ${String(error)}`);
    }
  }
  // A focused pane acknowledges its current stable notification before any
  // downstream surface consumes the snapshot. This keeps row styling,
  // Sketchybar, jump targets, and phone routing in lockstep on a visit.
  // Presence gates the visit: away from the machine, nothing acks, so a
  // parked-but-focused client cannot swallow the phone push.
  const present = isPresent(
    hostFacts.inputIdleSecs,
    clientFacts.latestClientActivityTs,
    Date.now() / 1000,
  );
  const acked = updateAcks(
    acks,
    settled,
    panes,
    clientFacts.focusedSessions,
    present,
  );
  const sessions = new Set(panes.map((pane) => pane.session));
  const hintsBySession = assignHints(settled, sessions, acked);
  writeHints(settled, hintsBySession, acked);
  publishAttention(settled, acked);
  const review = loadReviewSnapshot();
  publishReviewAttention(review.unacknowledged);
  pushPhone(settled, acked, present);

  // Pagination state, written by `rail page up|down`; the renderer clamps.
  let page = 0;
  try {
    page = Math.max(0, Number(readFileSync(PAGE_FILE, "utf8")) || 0);
  } catch {
    // No page file: top of the list.
  }

  const frames = new Map<string, string>();
  const visibleTargets: { paneId: string; tty: string; frame: string }[] = [];
  const hiddenTargets: {
    paneId: string;
    tty: string;
    frame: string;
    sessionAttached: boolean;
  }[] = [];
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
    const bucket = `${pane.session}\x1f${pane.width}\x1f${pane.height}\x1f${sprite}\x1f${page}\x1f${prefixHeld}\x1f${activeTab}\x1f${review.revision}`;
    let frame = frames.get(bucket);
    if (frame === undefined) {
      const data = {
        session: pane.session,
        activeTab,
        windows: windowsOf(panes, pane.session),
        agents: settled,
        review,
        tasks: taskSnapshot,
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
      countPaint();
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
    // Diff on the exact payload onResult stores, tty wrapping included.
    const payload = SYNC_ON + HIDE_CURSOR + frame + SYNC_OFF;
    if (pushed.get(pane.paneId) !== payload) {
      const target = { paneId: pane.paneId, tty: pane.tty, frame: payload };
      if (pane.windowActive && pane.sessionAttached) {
        visibleTargets.push(target);
      } else {
        hiddenTargets.push({
          ...target,
          sessionAttached: pane.sessionAttached,
        });
      }
    }
  }
  // The person-facing panes gate the refresh (wall-time ~= one pane);
  // everything off-screen drains behind them in likely-to-jump order.
  painter.fill(fillOrder(hiddenTargets));
  await painter.paintVisible(visibleTargets);

  // Forget panes that no longer exist so their ids can't shadow reused ones.
  const alive = new Set(panes.map((pane) => pane.paneId));
  for (const paneId of pushed.keys()) {
    if (!alive.has(paneId)) pushed.delete(paneId);
  }
  for (const key of lastTransmit.keys()) {
    if (!alive.has(key.slice(0, key.indexOf("\x1f")))) {
      lastTransmit.delete(key);
    }
  }

  lastEnabled = enabled;
  lastClientCount = clientFacts.clientCount;
  refreshCounter += 1;
  recordRefresh(refreshCounter, Date.now() - started);
}

// The scheduler's runner: failures stay inside (a rejected run must not
// kill the scheduling loop), and sustained dead-server failures on the
// exec path end the daemon exactly like the control client's onGone.
async function guardedRefresh(): Promise<void> {
  try {
    await refreshAndRender();
    noServerFails = 0;
  } catch (error) {
    logLine(`refresh failed: ${String(error)}`);
    noServerFails = NO_SERVER_PATTERN.test(String(error))
      ? noServerFails + 1
      : 0;
    if (noServerFails >= NO_SERVER_EXIT_FAILS) {
      await exitServerGone();
    }
  }
}

// Liveness alone is not holdership: an unclean death leaves the pidfile
// behind, and the pid can be reused by an unrelated process. The holder
// counts only while its command line is still a rail daemon — either
// runtime form (`…/tuis/rail/dist/daemon.mjs` bundled, or tsx running
// `src/daemon.ts` with the loader resolved under tuis/rail). The same
// pattern gates bin/rail's daemon_running; keep them in lockstep.
async function isRailDaemon(pid: number): Promise<boolean> {
  try {
    const { stdout } = await run("ps", ["-o", "command=", "-p", String(pid)]);
    return /rail.*daemon\.(ts|mjs)/.test(stdout);
  } catch {
    // ps fails for a dead pid.
    return false;
  }
}

// Exclusive-create (wx) makes the pidfile the lock itself: two daemons
// booting concurrently — tmux.conf sourcing races `rail on` — can both
// pass a check-then-write gate, but only one wins the create. A stale
// holder's file is unlinked and the claim retried; the loop is bounded
// for the pathological case where fresh claimants keep dying mid-race.
async function claimPidfile(): Promise<boolean> {
  for (let attempt = 0; attempt < 5; attempt++) {
    try {
      await writeFile(PID_FILE, String(process.pid), { flag: "wx" });
      return true;
    } catch {
      // Pidfile exists; reclaim below only if it's stale.
    }
    try {
      const pid = Number(await readFile(PID_FILE, "utf8"));
      if (pid > 0 && (await isRailDaemon(pid))) return false;
    } catch {
      // Unreadable pidfile: stale.
    }
    await unlink(PID_FILE).catch(() => {});
  }
  return false;
}

async function main(): Promise<void> {
  await mkdir(STATE_DIR, { recursive: true });
  if (!(await claimPidfile())) {
    logLine("rail daemon already running");
    process.exit(0);
  }

  // Telemetry on demand: `kill -USR2 $(cat daemon.pid)` drops the tick
  // ring, counters, and the scheduler's wake-reason counts into the log
  // as JSON lines, live, without touching the daemon's cadence.
  process.on("SIGUSR2", () => {
    logLine(`telemetry ${dump()}`);
    logLine(`refresh reasons ${JSON.stringify(scheduler.reasonCounts())}`);
  });

  // Instant agent updates: workmux hooks write a state file the moment an
  // agent changes status. The trigger floor coalesces heartbeat-churn
  // bursts into at most one workmux exec per second; the poller's content
  // compare keeps the non-changes from rendering.
  try {
    watch(join(WORKMUX_STATE, "agents"), () => {
      workmuxPoller.trigger(WORKMUX_TRIGGER_GAP_MS);
    });
  } catch {
    // Directory appears with the first agent; the 5s poll covers it.
  }
  // Theme/mascot switches rewrite the generated files: drop frame caches
  // so every pane repaints, and re-source tmux's own colors (this replaces
  // the statusline's theme-sync slot — the statusline is off while the
  // rail carries the chrome). A render touches every template output in a
  // burst; debounce so the burst costs one pass, not one per file event.
  let themePending: NodeJS.Timeout | null = null;
  let tuisColorsTouched = false;
  try {
    watch(GENERATED_DIR, (_event, filename) => {
      if (filename === "tuis-colors.json") tuisColorsTouched = true;
      if (themePending) clearTimeout(themePending);
      themePending = setTimeout(() => {
        if (tuisColorsTouched) pushed.clear();
        tuisColorsTouched = false;
        run(THEME_SYNC, []).catch(() => {});
        scheduler.request("theme");
      }, 30);
    });
  } catch {
    // Fresh install: no generated dir until the theme system's first
    // render. Palette reads fail the same way, so refreshes stay
    // unpainted until it lands; the watcher only returns on restart.
  }

  // The GitHub attention observer (launchd) rewrites its state file on
  // its own cadence; the mtime-gated loadReviewSnapshot stays the read
  // path, this watch just makes the refresh land within a beat.
  try {
    watch(ATTENTION_STATE_DIR, () => {
      scheduler.request("attention");
    });
  } catch {
    // No observer on this machine yet; the reconcile backstop covers it.
  }

  // enabled/tab/page are the launcher's files; everything else in
  // STATE_DIR is daemon output and must not wake (stateFileWake filters,
  // or every refresh would request the next one forever).
  let lastTab = loadRailTab();
  watch(STATE_DIR, (_event, filename) => {
    const currentTab = filename === "tab" ? loadRailTab() : lastTab;
    const wake = stateFileWake(filename, lastTab, currentTab);
    lastTab = currentTab;
    if (wake.vaultTriggerMs !== null) vaultPoller.trigger(wake.vaultTriggerMs);
    if (wake.refreshReason !== null) scheduler.request(wake.refreshReason);
  });

  if (!CONTROL_DISABLED) {
    control = startControlClient({
      events: {
        onNotification(name) {
          if (CONTROL_REFRESH_EVENTS.has(name)) {
            scheduler.request(name);
          } else if (
            !CONTROL_IGNORED_EVENTS.has(name) &&
            !unknownControlEvents.has(name)
          ) {
            // Once per name: a future tmux may grow notifications this
            // list has never heard of, and the log should say so without
            // becoming a firehose.
            unknownControlEvents.add(name);
            logLine(`unknown control notification: ${name}`);
          }
        },
        onConnect() {
          controlUp = true;
          scheduler.request("control-connect");
        },
        onDisconnect() {
          controlUp = false;
          scheduler.request("control-disconnect");
        },
        onGone() {
          void exitServerGone();
        },
      },
    });
  }

  // First refresh only after every slow source has loaded once, so the
  // first frames carry agents and tasks instead of flashing empty.
  await Promise.all([
    workmuxPoller.start(),
    vaultPoller.start(),
    hostPoller.start(),
    clientPoller.start(),
  ]);
  scheduler.request("boot");
  // Every slow source has loaded once: lift the gate so the boot refresh
  // (and anything the control client queued while connecting) fires now,
  // over populated state.
  scheduler.resume();

  // The reconcile backstop re-arms itself off the latest refresh's view
  // of enabled/clients; watchers and events still wake instantly either
  // way.
  function armReconcile(): void {
    const ms =
      !lastEnabled && lastClientCount === 0 ? IDLE_RECONCILE_MS : RECONCILE_MS;
    setTimeout(() => {
      scheduler.request("reconcile");
      armReconcile();
    }, ms);
  }
  armReconcile();
}

await main();
