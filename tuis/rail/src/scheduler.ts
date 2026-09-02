// The refresh scheduler: every wake source (control notifications, state
// file watches, poller changes, the reconcile backstop) funnels through
// request(), and the scheduler guarantees a refresh follows every
// request — a signal landing at any instant is never dropped.
//
// Shape: dirty flag + trailing-edge coalesce + single flight + post-run
// recheck. A burst of requests costs one refresh (fired coalesceMs after
// the burst began); requests that land mid-refresh set the dirty flag
// and the post-run recheck schedules the next one; minIntervalMs caps
// the refresh rate under a sustained signal storm.

import { logLine } from "./log.js";

export interface SchedulerTimers {
  setTimeout(fn: () => void, ms: number): unknown;
  clearTimeout(handle: unknown): void;
}

export interface RefreshSchedulerOptions {
  coalesceMs: number;
  minIntervalMs: number;
  // Start paused: request() accumulates the dirty flag but no refresh
  // fires until resume(). The daemon uses this so nothing runs before the
  // slow sources have loaded once — an early refresh (e.g. the control
  // client connecting) would otherwise paint and persist empty state.
  startPaused?: boolean;
  timers?: SchedulerTimers;
  now?: () => number;
}

export interface RefreshScheduler {
  request(reason: string): void;
  // Lift the startPaused gate and fire any refresh a request queued while
  // paused. A no-op once already running.
  resume(): void;
  // Cumulative request counts per reason — dumped alongside telemetry so
  // a chatty wake source is attributable after the fact.
  reasonCounts(): Record<string, number>;
  stop(): void;
}

export function makeRefreshScheduler(
  run: () => Promise<void>,
  options: RefreshSchedulerOptions,
): RefreshScheduler {
  const timers: SchedulerTimers = options.timers ?? {
    setTimeout: (fn, ms) => setTimeout(fn, ms),
    clearTimeout: (handle) => clearTimeout(handle as NodeJS.Timeout),
  };
  const now = options.now ?? Date.now;
  const counts: Record<string, number> = {};
  let dirty = false;
  let running = false;
  let stopped = false;
  let paused = options.startPaused ?? false;
  let timer: unknown = null;
  let lastStartedAt = -Infinity;

  function arm(): void {
    if (stopped || paused || running || timer !== null || !dirty) return;
    const delay = Math.max(
      options.coalesceMs,
      lastStartedAt + options.minIntervalMs - now(),
    );
    timer = timers.setTimeout(fire, delay);
  }

  function fire(): void {
    timer = null;
    if (stopped || running || !dirty) return;
    dirty = false;
    running = true;
    lastStartedAt = now();
    run()
      .catch((error: unknown) => {
        // The runner owns its own failure handling; this only keeps an
        // unexpected rejection from becoming an unhandled one.
        logLine(`refresh rejected: ${String(error)}`);
      })
      .finally(() => {
        running = false;
        // Post-run recheck: anything that landed mid-run set the dirty
        // flag, and this is the moment that turns it into a refresh.
        arm();
      });
  }

  return {
    request(reason: string): void {
      if (stopped) return;
      counts[reason] = (counts[reason] ?? 0) + 1;
      dirty = true;
      arm();
    },
    resume(): void {
      if (!paused) return;
      paused = false;
      arm();
    },
    reasonCounts: () => ({ ...counts }),
    stop(): void {
      stopped = true;
      if (timer !== null) {
        timers.clearTimeout(timer);
        timer = null;
      }
    },
  };
}
