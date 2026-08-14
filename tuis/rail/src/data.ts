import { execFile } from "node:child_process";
import { homedir } from "node:os";
import { promisify } from "node:util";

const run = promisify(execFile);

export type AgentStatus = "working" | "waiting" | "done";

export interface Agent {
  session: string;
  windowName: string;
  paneId: string;
  status: AgentStatus;
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
  windows: Window[];
  agents: Agent[];
}

// tmux formats can't contain our field separator; \x1f never appears in
// window names or pane ids.
const SEP = "\x1f";
const PANE_FORMAT = [
  "#{window_index}",
  "#{window_name}",
  "#{window_active}",
  "#{pane_id}",
].join(SEP);

async function collectWindows(session: string): Promise<Window[]> {
  const { stdout } = await run("tmux", [
    "list-panes",
    "-s",
    "-t",
    session,
    "-F",
    PANE_FORMAT,
  ]);
  const windows = new Map<number, Window>();
  for (const line of stdout.split("\n")) {
    if (!line) continue;
    const [index, name, active, paneId] = line.split(SEP);
    if (!index || !name || !paneId) continue;
    const idx = Number(index);
    const existing = windows.get(idx);
    if (existing) {
      existing.paneIds.push(paneId);
    } else {
      windows.set(idx, {
        index: idx,
        name,
        active: active === "1",
        paneIds: [paneId],
      });
    }
  }
  return [...windows.values()].sort((a, b) => a.index - b.index);
}

interface WorkmuxAgent {
  session: string;
  window_name: string;
  pane_id: string;
  status: string;
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

async function collectAgents(): Promise<Agent[]> {
  // Run from $HOME: `workmux status` scopes to the repository of its cwd,
  // and a non-repo cwd is what yields the global, all-projects view.
  const { stdout } = await run("workmux", ["status", "--json"], {
    cwd: homedir(),
  });
  const parsed = JSON.parse(stdout) as { agents?: WorkmuxAgent[] };
  return (parsed.agents ?? [])
    .filter((agent) => AGENT_STATUSES.has(agent.status))
    .map((agent) => ({
      session: agent.session,
      windowName: agent.window_name,
      paneId: agent.pane_id,
      status: agent.status as AgentStatus,
      title: agent.title ?? "",
      elapsedSecs: agent.elapsed_secs ?? 0,
      updatedTs: agent.updated_ts ?? 0,
      worktree: agent.worktree ?? "",
      branch: agent.branch ?? "",
    }));
}

export async function collect(session: string): Promise<RailData> {
  const [windows, agents] = await Promise.all([
    collectWindows(session),
    collectAgents(),
  ]);
  return { session, windows, agents };
}

export async function currentSession(): Promise<string> {
  const { stdout } = await run("tmux", ["display-message", "-p", "#S"]);
  return stdout.trim();
}

// ----- global snapshot (daemon) -----------------------------------------

export interface Pane {
  session: string;
  windowId: string;
  windowIndex: number;
  windowName: string;
  windowActive: boolean;
  windowPanes: number;
  paneId: string;
  tty: string;
  width: number;
  height: number;
  isRail: boolean;
}

const GLOBAL_FORMAT = [
  "#{session_name}",
  "#{window_id}",
  "#{window_index}",
  "#{window_name}",
  "#{window_active}",
  "#{window_panes}",
  "#{pane_id}",
  "#{pane_tty}",
  "#{pane_width}",
  "#{pane_height}",
  "#{@rail}",
].join(SEP);

// One tmux call per tick covers every session: rail panes to paint,
// content windows to list, and geometry for frame buckets.
export async function collectPanes(): Promise<Pane[]> {
  const { stdout } = await run("tmux", [
    "list-panes",
    "-a",
    "-F",
    GLOBAL_FORMAT,
  ]);
  const panes: Pane[] = [];
  for (const rawLine of stdout.split("\n")) {
    if (!rawLine) continue;
    const f = rawLine.split(SEP);
    if (f.length < 11) continue;
    panes.push({
      session: f[0]!,
      windowId: f[1]!,
      windowIndex: Number(f[2]!),
      windowName: f[3]!,
      windowActive: f[4] === "1",
      windowPanes: Number(f[5]!),
      paneId: f[6]!,
      tty: f[7]!,
      width: Number(f[8]!),
      height: Number(f[9]!),
      isRail: f[10] === "1",
    });
  }
  return panes;
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
