// tmux control-mode client: the daemon's event source. One long-lived
// `tmux -C attach-session` per server delivers structural notifications
// (%window-add, %session-window-changed, ...) the moment they happen and
// answers read commands over its own socket — so the steady state needs
// no polling execs at all. Events are WAKE SIGNALS only; the snapshot
// read (sent through command()) remains the source of truth, and
// mutations stay on the exec path so a wedged control client can never
// block self-healing.
//
// Attached with `-f no-output,no-detach-on-destroy` (verified on this
// machine's tmux 3.7c): no %output lines ever arrive, and destroying the
// attached session moves the client instead of killing it. The client
// lives while its stdin stays open; stdin EOF (or %exit) ends it.

import { spawn } from "node:child_process";

import { run } from "./data.js";
import { logLine } from "./log.js";

// ----- line protocol -----------------------------------------------------

// What one parsed line (or completed reply block) means. Commands answer
// inside %begin/%end (%error on failure) fences; everything else outside
// a fence is a notification.
export type ControlEvent =
  | { kind: "block"; error: boolean; output: string }
  | { kind: "notification"; name: string; line: string };

// Line-buffered and chunk-agnostic: feed() accepts arbitrary splits of
// the byte stream and emits events only for complete lines. Reply-block
// fences are matched positionally — tmux never interleaves notifications
// inside a block.
export class ControlParser {
  private buffer = "";
  private inBlock = false;
  private blockLines: string[] = [];

  feed(chunk: string): ControlEvent[] {
    const events: ControlEvent[] = [];
    this.buffer += chunk;
    let newline = this.buffer.indexOf("\n");
    while (newline !== -1) {
      let line = this.buffer.slice(0, newline);
      this.buffer = this.buffer.slice(newline + 1);
      // tmux emits \r\n when stdout looks tty-like; tolerate both.
      if (line.endsWith("\r")) line = line.slice(0, -1);
      const event = this.parseLine(line);
      if (event) events.push(event);
      newline = this.buffer.indexOf("\n");
    }
    return events;
  }

  private parseLine(line: string): ControlEvent | null {
    if (this.inBlock) {
      if (line.startsWith("%end ") || line === "%end") {
        this.inBlock = false;
        return {
          kind: "block",
          error: false,
          output: this.blockLines.join("\n"),
        };
      }
      if (line.startsWith("%error ") || line === "%error") {
        this.inBlock = false;
        return {
          kind: "block",
          error: true,
          output: this.blockLines.join("\n"),
        };
      }
      this.blockLines.push(line);
      return null;
    }
    if (line.startsWith("%begin")) {
      this.inBlock = true;
      this.blockLines = [];
      return null;
    }
    if (line.startsWith("%")) {
      const space = line.indexOf(" ");
      return {
        kind: "notification",
        name: space === -1 ? line : line.slice(0, space),
        line,
      };
    }
    // Bare text outside a block should not happen with no-output set;
    // dropping it beats corrupting the reply correlation.
    return null;
  }
}

// ----- client ------------------------------------------------------------

// The narrow child surface the client needs — injectable for tests.
export interface ControlChild {
  write(data: string): void;
  kill(): void;
  onData(listener: (chunk: string) => void): void;
  onExit(listener: () => void): void;
}

export interface ControlTarget {
  socketPath: string;
  session: string;
}

export interface ControlClientEvents {
  onNotification: (name: string, line: string) => void;
  onConnect: () => void;
  onDisconnect: () => void;
  // The server has answered nothing for goneAfterMs of reconnect
  // attempts: it is gone, not restarting. The daemon exits cleanly on
  // this (today's NO_SERVER contract) and ensure-daemon revives it with
  // the next server.
  onGone: () => void;
}

export interface ControlTimers {
  setTimeout(fn: () => void, ms: number): unknown;
  clearTimeout(handle: unknown): void;
}

export interface ControlClientOptions {
  events: ControlClientEvents;
  findTarget?: () => Promise<ControlTarget>;
  spawnChild?: (target: ControlTarget) => ControlChild;
  reconnectDelaysMs?: readonly number[];
  goneAfterMs?: number;
  commandTimeoutMs?: number;
  timers?: ControlTimers;
  now?: () => number;
}

export interface ControlClient {
  // Send one tmux command line; resolves with the reply block's output.
  // Rejects while disconnected — callers fall back to the exec path.
  command(commandLine: string): Promise<string>;
  connected(): boolean;
  stop(): void;
}

// Backoff ladder between reconnect attempts: fast enough that a server
// restart reconnects within a beat, capped so a long outage costs a
// probe every 2s (the same cadence the old dead-server backoff used).
const RECONNECT_DELAYS_MS: readonly number[] = [100, 200, 400, 800, 1600, 2000];
// ~10s of sustained failure = the server died, not hiccuped.
const GONE_AFTER_MS = 10_000;
// A reply that never arrives means a wedged client; replace it rather
// than holding a refresh hostage.
const COMMAND_TIMEOUT_MS = 10_000;

const TARGET_SEP = "\x1f";

// The first session on the server — which session is irrelevant (the
// client only listens and reads), but attach-session needs one. The same
// probe doubles as the is-the-server-alive check for the gone ladder.
async function defaultFindTarget(): Promise<ControlTarget> {
  const { stdout } = await run("tmux", [
    "list-sessions",
    "-F",
    `#{socket_path}${TARGET_SEP}#{session_name}`,
  ]);
  const first = stdout.split("\n").find((line) => line !== "");
  if (!first) throw new Error("no server running (no sessions)");
  const sep = first.indexOf(TARGET_SEP);
  return { socketPath: first.slice(0, sep), session: first.slice(sep + 1) };
}

function defaultSpawnChild(target: ControlTarget): ControlChild {
  const env = { ...process.env };
  // The daemon usually inherits $TMUX from run-shell, and a set $TMUX
  // makes attach-session refuse with the nested-sessions warning. The
  // explicit -S pins the exact same server without it.
  delete env["TMUX"];
  delete env["TMUX_PANE"];
  const child = spawn(
    "tmux",
    [
      "-S",
      target.socketPath,
      "-C",
      "attach-session",
      "-f",
      "no-output,no-detach-on-destroy",
      "-t",
      target.session,
    ],
    // stdin MUST stay piped and open: control clients exit on stdin EOF.
    { stdio: ["pipe", "pipe", "ignore"], env },
  );
  child.stdout.setEncoding("utf8");
  return {
    write: (data) => {
      child.stdin.write(data);
    },
    kill: () => {
      child.kill("SIGTERM");
    },
    onData: (listener) => {
      child.stdout.on("data", listener);
    },
    onExit: (listener) => {
      child.on("exit", listener);
      // spawn failures (ENOENT) surface here instead of throwing.
      child.on("error", listener);
    },
  };
}

interface PendingCommand {
  resolve: (output: string) => void;
  reject: (error: Error) => void;
  timer: unknown;
}

export function startControlClient(
  options: ControlClientOptions,
): ControlClient {
  const { events } = options;
  const findTarget = options.findTarget ?? defaultFindTarget;
  const spawnChild = options.spawnChild ?? defaultSpawnChild;
  const delays = options.reconnectDelaysMs ?? RECONNECT_DELAYS_MS;
  const goneAfterMs = options.goneAfterMs ?? GONE_AFTER_MS;
  const commandTimeoutMs = options.commandTimeoutMs ?? COMMAND_TIMEOUT_MS;
  const timers: ControlTimers = options.timers ?? {
    setTimeout: (fn, ms) => setTimeout(fn, ms),
    clearTimeout: (handle) => clearTimeout(handle as NodeJS.Timeout),
  };
  const now = options.now ?? Date.now;

  let child: ControlChild | null = null;
  let parser = new ControlParser();
  // FIFO correlation: tmux answers command lines in the order they were
  // written, so the oldest pending entry owns the next completed block.
  let pending: PendingCommand[] = [];
  let handshaken = false;
  let stopped = false;
  let attempt = 0;
  let downSince: number | null = null;
  let reconnectHandle: unknown = null;

  function failPending(error: Error): void {
    const failed = pending;
    pending = [];
    for (const entry of failed) {
      timers.clearTimeout(entry.timer);
      entry.reject(error);
    }
  }

  function disconnect(): void {
    if (child === null) return;
    const current = child;
    child = null;
    try {
      current.kill();
    } catch {
      // Already dead.
    }
    const wasConnected = handshaken;
    handshaken = false;
    failPending(new Error("control client disconnected"));
    if (wasConnected) events.onDisconnect();
    if (!stopped) scheduleReconnect();
  }

  function scheduleReconnect(): void {
    if (reconnectHandle !== null || stopped) return;
    const delay = delays[Math.min(attempt, delays.length - 1)] ?? 2000;
    attempt += 1;
    reconnectHandle = timers.setTimeout(() => {
      reconnectHandle = null;
      void connect();
    }, delay);
  }

  function handleEvent(event: ControlEvent, source: ControlChild): void {
    if (child !== source) return; // a late chunk from a replaced child
    if (event.kind === "block") {
      if (!handshaken) {
        // The first block is the attach command's own (empty) reply —
        // the connection handshake, never an answer to command().
        handshaken = true;
        attempt = 0;
        downSince = null;
        events.onConnect();
        return;
      }
      const entry = pending.shift();
      if (entry === undefined) return; // unsolicited block; nothing waits
      timers.clearTimeout(entry.timer);
      if (event.error) {
        entry.reject(new Error(event.output || "tmux control command failed"));
      } else {
        entry.resolve(event.output);
      }
      return;
    }
    if (event.name === "%exit") {
      // tmux announces the client's own death; the process exit follows.
      disconnect();
      return;
    }
    events.onNotification(event.name, event.line);
  }

  async function connect(): Promise<void> {
    if (stopped || child !== null) return;
    let target: ControlTarget;
    try {
      target = await findTarget();
    } catch {
      const at = now();
      downSince ??= at;
      if (at - downSince >= goneAfterMs) {
        events.onGone();
        return;
      }
      scheduleReconnect();
      return;
    }
    // The server answered list-sessions: alive, whatever the attach does.
    downSince = null;
    let spawned: ControlChild;
    try {
      spawned = spawnChild(target);
    } catch (error) {
      logLine(`control client spawn failed: ${String(error)}`);
      scheduleReconnect();
      return;
    }
    parser = new ControlParser();
    handshaken = false;
    child = spawned;
    spawned.onData((chunk) => {
      for (const event of parser.feed(chunk)) handleEvent(event, spawned);
    });
    spawned.onExit(() => {
      if (child === spawned) disconnect();
    });
  }

  void connect();

  return {
    command(commandLine: string): Promise<string> {
      if (commandLine.includes("\n")) {
        return Promise.reject(new Error("control commands are single lines"));
      }
      const current = child;
      if (current === null || !handshaken) {
        return Promise.reject(new Error("control client not connected"));
      }
      return new Promise<string>((resolve, reject) => {
        const entry: PendingCommand = {
          resolve,
          reject,
          timer: timers.setTimeout(() => {
            reject(new Error(`control command timed out: ${commandLine}`));
            disconnect();
          }, commandTimeoutMs),
        };
        pending.push(entry);
        try {
          current.write(`${commandLine}\n`);
        } catch {
          // A dead pipe surfaces via onExit -> disconnect -> failPending.
        }
      });
    },
    connected: () => child !== null && handshaken,
    stop(): void {
      stopped = true;
      if (reconnectHandle !== null) {
        timers.clearTimeout(reconnectHandle);
        reconnectHandle = null;
      }
      disconnect();
    },
  };
}
