import { execFile } from "node:child_process";
import { readdirSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { promisify } from "node:util";

import type { ReviewSnapshot } from "./attention/review.js";
import type { RailTabId } from "./tabs.js";
import type { TaskSnapshot } from "./tasks.js";

// The one exec plumbing every module shares.
export const run = promisify(execFile);
export const tmux = (...args: string[]) => run("tmux", args);

export type AgentStatus = "working" | "waiting" | "done";

export interface Agent {
  session: string;
  windowName: string;
  paneId: string;
  agentKind?: string;
  status: AgentStatus;
  // Workmux's status transition time. Unlike updatedTs, this does not move
  // when a state file is rewritten for a heartbeat or title change.
  statusTs: number;
  title: string;
  elapsedSecs: number;
  updatedTs: number;
  worktree: string;
  branch: string;
}

export interface Window {
  index: number;
  name: string;
  active: boolean;
  paneIds: string[];
}

export interface RailData {
  session: string;
  activeTab: RailTabId;
  windows: Window[];
  agents: Agent[];
  review: ReviewSnapshot;
  tasks: TaskSnapshot;
  // Pane ids whose current waiting/done notification has been acknowledged.
  acked: Set<string>;
  // Jump-hint digit per agent pane id (alt+space <digit> on Agents),
  // viewer-relative.
  hints: Map<string, string>;
  // Kitty image id for the footer sprite; null reclaims the footer rows
  // for content.
  sprite: number | null;
  // Pagination page for the body (0 = top); clamped by the renderer.
  page: number;
  // A client on this session is holding the tmux prefix or sitting in
  // the focused-tab element table — the header recolors as the mode signal.
  prefixHeld: boolean;
}

// tmux formats can't contain our field separator; \x1f never appears in
// window names or pane ids.
const SEP = "\x1f";
const WORKMUX_AGENTS_DIR = join(homedir(), ".local/state/workmux/agents");

interface WorkmuxAgentState {
  pane_key?: { pane_id?: unknown };
  status_ts?: unknown;
}

interface WorkmuxAgent {
  session: string;
  window_name: string;
  pane_id: string;
  agent_kind?: string;
  status: string;
  status_ts?: number | null;
  title: string;
  elapsed_secs: number;
  updated_ts: number;
  worktree: string;
  branch: string;
}

const AGENT_STATUSES: ReadonlySet<string> = new Set([
  "working",
  "waiting",
  "done",
]);

// `workmux status --json` does not include status_ts in installed releases,
// although the per-agent state files retain it. Read that authoritative
// transition timestamp so heartbeat/title writes cannot reset the grace
// period. A future Workmux JSON field still wins in collectAgents below.
export function loadStatusTransitionTimes(
  agentsDir = WORKMUX_AGENTS_DIR,
): Map<string, number> {
  let files;
  try {
    files = readdirSync(agentsDir, { withFileTypes: true });
  } catch {
    return new Map();
  }

  const timestamps = new Map<string, number>();
  for (const file of files) {
    if (!file.isFile() || !file.name.endsWith(".json")) continue;
    try {
      const state = JSON.parse(
        readFileSync(join(agentsDir, file.name), "utf8"),
      ) as WorkmuxAgentState;
      const paneId = state.pane_key?.pane_id;
      const statusTs = state.status_ts;
      if (
        typeof paneId === "string" &&
        typeof statusTs === "number" &&
        Number.isFinite(statusTs)
      ) {
        timestamps.set(paneId, statusTs);
      }
    } catch {
      // Workmux can rewrite a state file while the directory is read.
    }
  }
  return timestamps;
}

async function collectAgents(): Promise<Agent[]> {
  // Run from $HOME: `workmux status` scopes to the repository of its cwd,
  // and a non-repo cwd is what yields the global, all-projects view.
  // execFile's default 1MB maxBuffer rejects on a large agent fleet — the
  // caller's catch would then hold stale agents forever with no error in
  // sight. The timeout keeps a hung workmux from wedging every tick.
  const { stdout } = await run("workmux", ["status", "--json"], {
    cwd: homedir(),
    maxBuffer: 8 * 1024 * 1024,
    timeout: 10_000,
  });
  const parsed = JSON.parse(stdout) as { agents?: WorkmuxAgent[] };
  const transitionTimes = loadStatusTransitionTimes();
  return (parsed.agents ?? [])
    .filter((agent) => AGENT_STATUSES.has(agent.status))
    .map((agent) => ({
      session: agent.session,
      windowName: agent.window_name,
      paneId: agent.pane_id,
      agentKind: agent.agent_kind ?? "",
      status: agent.status as AgentStatus,
      statusTs: agent.status_ts ?? transitionTimes.get(agent.pane_id) ?? 0,
      title: agent.title ?? "",
      elapsedSecs: agent.elapsed_secs ?? 0,
      updatedTs: agent.updated_ts ?? 0,
      worktree: agent.worktree ?? "",
      branch: agent.branch ?? "",
    }));
}

// A waiting or done transition must remain visible in Workmux for this long
// before it becomes the live status used by attention surfaces. The age comes
// from Workmux's status_ts, not updated_ts: the latter also changes for
// heartbeats and title updates. Working transitions are accepted immediately
// so a transient waiting state can disappear completely.
//
// The daemon re-reads `workmux status` every 5s, so 60s asks for about twelve
// observations. The window is long enough to ride out Codex's brief
// auto-classification waiting state without delaying a real return to work.
//
// The floor is the reconcile interval: below it this suppresses nothing.
export const AGENT_STATUS_LAG_SECS = 60;

export interface StableAgentState {
  status: AgentStatus;
  statusTs: number;
}

export function stabilizeAgents(
  agents: Agent[],
  stableStatuses: Map<string, StableAgentState>,
  nowSecs: number,
): Agent[] {
  const live = new Set(agents.map((agent) => agent.paneId));
  for (const paneId of stableStatuses.keys()) {
    if (!live.has(paneId)) stableStatuses.delete(paneId);
  }

  return agents.map((agent) => {
    const stable = stableStatuses.get(agent.paneId);
    // Returning to working is authoritative. Holding on to a stale waiting
    // or done state here would make a live agent look blocked and would let
    // an old notification keep it in attention surfaces.
    if (agent.status === "working") {
      stableStatuses.set(agent.paneId, {
        status: agent.status,
        statusTs: agent.statusTs,
      });
      return agent;
    }

    const recent = nowSecs - agent.statusTs < AGENT_STATUS_LAG_SECS;
    if (recent && stable === undefined) {
      // There is no earlier observation to restore, so treat a fresh
      // non-working status as provisional working until it settles.
      stableStatuses.set(agent.paneId, {
        status: "working",
        statusTs: agent.statusTs,
      });
      return { ...agent, status: "working" };
    }
    if (recent && stable !== undefined && stable.status !== agent.status) {
      return {
        ...agent,
        status: stable.status,
        statusTs: stable.statusTs,
      };
    }
    stableStatuses.set(agent.paneId, {
      status: agent.status,
      statusTs: agent.statusTs,
    });
    return agent;
  });
}

// ----- global snapshot (daemon) -----------------------------------------

export interface Pane {
  session: string;
  sessionAttached: boolean;
  windowId: string;
  windowIndex: number;
  windowName: string;
  windowActive: boolean;
  windowPanes: number;
  windowWidth: number;
  paneId: string;
  paneActive: boolean;
  tty: string;
  width: number;
  height: number;
  isRail: boolean;
  historySize: number;
  inMode: boolean;
}

// Both listings run as ONE `;`-joined tmux invocation per tick — one
// process spawn instead of two, measured at ~2x on poll cost. The
// leading tag says which command produced each output line.
const PANE_TAG = "P";
const CLIENT_TAG = "C";

// No #{session_attached} here: the daemon's control-mode client counts
// as attached and would poison it, so sessionAttached derives from the
// FILTERED client rows instead (attachedSessions below).
const PANE_FORMAT = [
  PANE_TAG,
  "#{session_name}",
  "#{window_id}",
  "#{window_index}",
  "#{window_name}",
  "#{window_active}",
  "#{window_panes}",
  "#{window_width}",
  "#{pane_id}",
  "#{pane_active}",
  "#{pane_tty}",
  "#{pane_width}",
  "#{pane_height}",
  "#{@rail}",
  "#{history_size}",
  "#{pane_in_mode}",
].join(SEP);

function parsePane(f: string[], attachedSessions: Set<string>): Pane | null {
  if (f.length < 15) return null;
  return {
    session: f[0]!,
    sessionAttached: attachedSessions.has(f[0]!),
    windowId: f[1]!,
    windowIndex: Number(f[2]!),
    windowName: f[3]!,
    windowActive: f[4] === "1",
    windowPanes: Number(f[5]!),
    windowWidth: Number(f[6]!),
    paneId: f[7]!,
    paneActive: f[8] === "1",
    tty: f[9]!,
    width: Number(f[10]!),
    height: Number(f[11]!),
    isRail: f[12] === "1",
    historySize: Number(f[13]!),
    inMode: f[14] === "1",
  };
}

export interface ClientFacts {
  // Sessions whose attached client is mid-chord: tmux prefix held, or
  // the focused-tab element table active.
  modeSessions: Set<string>;
  // Sessions with an attached client that lacks kitty graphics. Both
  // mascot halves must skip these: transmission, because tmux forwards
  // the passthrough to every viewing client and a non-kitty client
  // prints the multi-KB payload as literal text; frame content, because
  // placeholder cells garble a non-kitty viewer (see below) and frames
  // persist in tmux's buffers per session.
  nonKittySessions: Set<string>;
  // Most recent activity timestamp (epoch secs) across attached clients;
  // null with no clients. The non-macOS stand-in for input-idle presence.
  latestClientActivityTs: number | null;
  // Sessions whose attached terminal window currently owns OS focus. The
  // terminal reports it (focus-events), so this is per-client, travels
  // over ssh, and is true only while someone is actually looking.
  focusedSessions: Set<string>;
  // Whether the most recently active client renders kitty graphics.
  // Placeholder cells need this bit AND a session clear of
  // nonKittySessions: a terminal without the protocol cannot even LAY
  // OUT the placeholder text (astral codepoint plus combining diacritics
  // desync its column accounting and garble the whole pane). Same
  // contract as window-size latest — machine hand-offs repaint within a
  // tick, same-machine switches never change it.
  latestClientIsKitty: boolean;
  // Attached clients server-wide; zero lets the daemon idle its cadence.
  clientCount: number;
  // Sessions with at least one REAL client attached. Panes derive
  // sessionAttached from this set rather than #{session_attached},
  // which cannot tell a person from the daemon's own control client.
  attachedSessions: Set<string>;
}

// Every fact here is about PEOPLE at terminals, so the daemon's own
// control-mode client is filtered out of all of them — it holds no
// prefix, renders nothing, and its activity timestamp is machine noise.
const CLIENT_FORMAT = [
  CLIENT_TAG,
  "#{client_session}",
  "#{client_prefix}",
  "#{client_key_table}",
  "#{client_termname}",
  "#{client_activity}",
  "#{client_flags}",
  "#{client_control_mode}",
].join(SEP);

function clientFactsFrom(rows: string[][]): ClientFacts {
  const modeSessions = new Set<string>();
  const nonKittySessions = new Set<string>();
  const focusedSessions = new Set<string>();
  const attachedSessions = new Set<string>();
  // No clients at all: keep mascots in the buffers for the usual
  // capable reattach.
  let latestClientIsKitty = true;
  let latestActivity = -1;
  let clientCount = 0;
  for (const [
    session,
    prefix,
    keyTable,
    termname,
    activity,
    flags,
    controlMode,
  ] of rows) {
    if (!session || controlMode === "1") continue;
    clientCount += 1;
    attachedSessions.add(session);
    const kitty = /ghostty|kitty/i.test(termname ?? "");
    if (prefix === "1" || keyTable === "tab") modeSessions.add(session);
    if (!kitty) nonKittySessions.add(session);
    if ((flags ?? "").split(",").includes("focused")) {
      focusedSessions.add(session);
    }
    const activityTs = Number(activity) || 0;
    if (activityTs >= latestActivity) {
      latestActivity = activityTs;
      latestClientIsKitty = kitty;
    }
  }
  return {
    modeSessions,
    nonKittySessions,
    latestClientActivityTs: latestActivity >= 0 ? latestActivity : null,
    focusedSessions,
    latestClientIsKitty,
    clientCount,
    attachedSessions,
  };
}

export interface Snapshot {
  panes: Pane[];
  clientFacts: ClientFacts;
}

// Tagged listing output (panes + clients, any order) into one Snapshot.
// Client rows resolve first: pane attachment derives from them.
export function parseSnapshot(stdout: string): Snapshot {
  const paneRows: string[][] = [];
  const clientRows: string[][] = [];
  for (const rawLine of stdout.split("\n")) {
    if (!rawLine) continue;
    const [tag, ...f] = rawLine.split(SEP);
    if (tag === PANE_TAG) {
      paneRows.push(f);
    } else if (tag === CLIENT_TAG) {
      clientRows.push(f);
    }
  }
  const clientFacts = clientFactsFrom(clientRows);
  const panes: Pane[] = [];
  for (const f of paneRows) {
    const pane = parsePane(f, clientFacts.attachedSessions);
    if (pane) panes.push(pane);
  }
  return { panes, clientFacts };
}

// A way to run the listings without an exec: the daemon passes the
// control client's command() here, and each string is one tmux command
// line answered over the control socket.
export type SnapshotRunner = (commandLine: string) => Promise<string>;

// The whole tmux poll — every session's panes plus the client table.
// Through a runner it costs zero processes; the exec fallback (control
// down or disabled) batches both listings into one invocation.
// Just the client facts, from a lone list-clients — no list-panes. The
// control protocol has no notification for prefix-held, key-table, or
// client focus, so those bits (which the rail paints live) are polled
// cheaply on their own cadence instead of riding the expensive pane
// snapshot or waiting out the reconcile backstop.
export async function collectClientFacts(
  runner?: SnapshotRunner,
): Promise<ClientFacts> {
  const out = runner
    ? await runner(`list-clients -F '${CLIENT_FORMAT}'`)
    : (await run("tmux", ["list-clients", "-F", CLIENT_FORMAT])).stdout;
  const rows: string[][] = [];
  for (const line of out.split("\n")) {
    if (!line.startsWith(`${CLIENT_TAG}${SEP}`)) continue;
    rows.push(line.split(SEP).slice(1));
  }
  return clientFactsFrom(rows);
}

// The render-affecting client bits, order-stable, so a poller can tell a
// meaningful change from mere activity-timestamp churn.
export function clientModeSignature(facts: ClientFacts): string {
  const sorted = (set: Set<string>): string => [...set].sort().join(",");
  return [
    sorted(facts.modeSessions),
    sorted(facts.focusedSessions),
    sorted(facts.nonKittySessions),
    facts.clientCount,
    facts.latestClientIsKitty ? "1" : "0",
  ].join("|");
}

export async function collectSnapshot(
  runner?: SnapshotRunner,
): Promise<Snapshot> {
  if (runner) {
    const [paneOut, clientOut] = await Promise.all([
      runner(`list-panes -a -F '${PANE_FORMAT}'`),
      runner(`list-clients -F '${CLIENT_FORMAT}'`),
    ]);
    return parseSnapshot(`${paneOut}\n${clientOut}`);
  }
  const { stdout } = await run("tmux", [
    "list-panes",
    "-a",
    "-F",
    PANE_FORMAT,
    ";",
    "list-clients",
    "-F",
    CLIENT_FORMAT,
  ]);
  return parseSnapshot(stdout);
}

// Content windows of one session, rail panes excluded — the rail never
// lists itself.
export function windowsOf(panes: Pane[], session: string): Window[] {
  const windows = new Map<number, Window>();
  for (const pane of panes) {
    if (pane.session !== session || pane.isRail) continue;
    const existing = windows.get(pane.windowIndex);
    if (existing) {
      existing.paneIds.push(pane.paneId);
    } else {
      windows.set(pane.windowIndex, {
        index: pane.windowIndex,
        name: pane.windowName,
        active: pane.windowActive,
        paneIds: [pane.paneId],
      });
    }
  }
  return [...windows.values()].sort((a, b) => a.index - b.index);
}

export { collectAgents };
