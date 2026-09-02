// Per-source wall-clock pollers. Each slow source (workmux, vault,
// ioreg) owns its own cadence instead of riding a shared tick counter,
// caches its latest value for the refresh path to read, and reports a
// change only when the CONTENT changed — so heartbeat churn stops
// causing renders. trigger() asks for an earlier poll while enforcing a
// minimum gap since the last one (the churn floor), and loads are
// single-flight: a trigger landing mid-load runs after it, never beside
// it.

import { logLine } from "./log.js";

export interface PollerTimers {
  setTimeout(fn: () => void, ms: number): unknown;
  clearTimeout(handle: unknown): void;
}

export interface PollerOptions<T> {
  name: string;
  // Re-read after every poll, so a cadence that depends on state (the
  // vault's tasks-tab vs elsewhere split) switches on the next arm.
  intervalMs: () => number;
  load: () => Promise<T>;
  changed: (previous: T, next: T) => boolean;
  onChange: (next: T) => void;
  timers?: PollerTimers;
  now?: () => number;
}

export interface Poller<T> {
  // Latest successfully loaded value; undefined before the first load.
  value(): T | undefined;
  // Poll soon, but no sooner than minGapMs after the last poll started.
  trigger(minGapMs: number): void;
  // Kick the first poll immediately; resolves when it settles.
  start(): Promise<void>;
  stop(): void;
}

export function makePoller<T>(options: PollerOptions<T>): Poller<T> {
  const timers: PollerTimers = options.timers ?? {
    setTimeout: (fn, ms) => setTimeout(fn, ms),
    clearTimeout: (handle) => clearTimeout(handle as NodeJS.Timeout),
  };
  const now = options.now ?? Date.now;

  let latest: T | undefined;
  let loading = false;
  let stopped = false;
  let failing = false;
  let lastStartedAt = -Infinity;
  let timer: unknown = null;
  let timerDueAt = Infinity;
  // Earliest due time requested by a trigger that landed mid-load.
  let pendingDueAt: number | null = null;

  // Keep whichever timer fires earlier — a trigger may pull the next
  // poll forward, but never pushes an already-armed earlier one back.
  function armAt(dueAt: number): void {
    if (stopped) return;
    if (timer !== null) {
      if (timerDueAt <= dueAt) return;
      timers.clearTimeout(timer);
      timer = null;
    }
    timerDueAt = dueAt;
    timer = timers.setTimeout(
      () => {
        timer = null;
        timerDueAt = Infinity;
        void poll();
      },
      Math.max(0, dueAt - now()),
    );
  }

  async function poll(): Promise<void> {
    if (stopped || loading) return;
    loading = true;
    lastStartedAt = now();
    try {
      const next = await options.load();
      const isChanged = latest === undefined || options.changed(latest, next);
      latest = next;
      failing = false;
      if (isChanged && !stopped) options.onChange(next);
    } catch (error) {
      // Transient source failure: keep painting the last known value,
      // and say so once per failure streak — silent staleness lies.
      if (!failing) {
        failing = true;
        logLine(
          `${options.name} poll failed; keeping last value: ${String(error)}`,
        );
      }
    } finally {
      loading = false;
      const dueAt = pendingDueAt ?? lastStartedAt + options.intervalMs();
      pendingDueAt = null;
      armAt(dueAt);
    }
  }

  return {
    value: () => latest,
    trigger(minGapMs: number): void {
      if (stopped) return;
      const dueAt = Math.max(now(), lastStartedAt + minGapMs);
      if (loading) {
        pendingDueAt = Math.min(pendingDueAt ?? Infinity, dueAt);
        return;
      }
      armAt(dueAt);
    },
    start(): Promise<void> {
      return poll();
    },
    stop(): void {
      stopped = true;
      if (timer !== null) {
        timers.clearTimeout(timer);
        timer = null;
      }
    },
  };
}

// ----- state-file wake policy -------------------------------------------

// What a write inside the rail's STATE_DIR wakes. Only the three files
// the shell launcher writes (enabled, tab, page) wake anything —
// everything else in that directory is the daemon's OWN output (hints,
// acks, attention, stability, pidfile), and waking on those would make
// every refresh request the next one, forever.
export interface StateFileWake {
  refreshReason: string | null;
  // Minimum-gap trigger for the vault poller; only switching TO the
  // tasks tab re-reads the vault early (the visit makes the list
  // current), and the gap keeps tab-bouncing from hammering it.
  vaultTriggerMs: number | null;
}

export const VAULT_TAB_TRIGGER_MS = 2000;

export function stateFileWake(
  filename: string | null,
  previousTab: string,
  currentTab: string,
): StateFileWake {
  if (filename !== "enabled" && filename !== "tab" && filename !== "page") {
    return { refreshReason: null, vaultTriggerMs: null };
  }
  return {
    refreshReason: `state:${filename}`,
    vaultTriggerMs:
      filename === "tab" && currentTab === "tasks" && previousTab !== "tasks"
        ? VAULT_TAB_TRIGGER_MS
        : null,
  };
}
