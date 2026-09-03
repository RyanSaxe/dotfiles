// Where the daemon's time goes. Pure observation — nothing here may feed
// back into behavior. The ring holds the last 256 refreshes; SIGUSR2
// (daemon.ts) dumps ring + counters to the log on demand, and any refresh
// that overruns its own cadence logs its breakdown the moment it happens,
// since by the time anyone asks the ring may have rolled past it.

import { logLine } from "./log.js";

// snapshot/workmux/vault/selfHeal time the awaits in the refresh. ioreg
// times the collectHostFacts await, which mostly reads a cache — the exec
// is time-gated inside probes.ts. paintCount counts frames BUILT (one
// renderRail per bucket); panesPainted counts rail ttys actually written.
export interface RefreshRecord {
  totalMs: number;
  snapshotMs: number;
  workmuxMs: number;
  vaultMs: number;
  ioregMs: number;
  selfHealMs: number;
  paintCount: number;
  panesPainted: number;
  refreshCounter: number;
}

type Span = "snapshot" | "workmux" | "vault" | "ioreg" | "selfHeal" | "client";

const SLOW_REFRESH_MS = 250;
const SLOW_LOG_WINDOW_MS = 10_000;
let lastSlowLogged = 0;
let slowSuppressed = 0;
const RING_SIZE = 256;
const ring: RefreshRecord[] = [];
let ringNext = 0;

const spans: Record<Span, number> = {
  snapshot: 0,
  workmux: 0,
  vault: 0,
  ioreg: 0,
  selfHeal: 0,
  client: 0,
};
let paintCount = 0;
let panesPainted = 0;

// Span starts double as cumulative dispatch counts: snapshot, workmux, and
// vault each map 1:1 to an exec; ioreg and selfHeal count calls.
const counters: { refreshes: number; spans: Record<Span, number> } = {
  refreshes: 0,
  spans: {
    snapshot: 0,
    workmux: 0,
    vault: 0,
    ioreg: 0,
    selfHeal: 0,
    client: 0,
  },
};

// Time one awaited leg without serializing it — the refresh's Promise.all
// stays concurrent, and rejection passes through untouched.
export function timed<T>(span: Span, work: Promise<T>): Promise<T> {
  const started = Date.now();
  counters.spans[span] += 1;
  return work.finally(() => {
    spans[span] = Date.now() - started;
  });
}

export function countPaint(): void {
  paintCount += 1;
}

export function countPanePainted(): void {
  panesPainted += 1;
}

// Close out one refresh: ring the record, reset the accumulators. Failed
// refreshes never get here, so their partial spans ride into the next
// record — accepted; the failure itself is already logged.
export function recordRefresh(refreshCounter: number, totalMs: number): void {
  const record: RefreshRecord = {
    totalMs,
    snapshotMs: spans.snapshot,
    workmuxMs: spans.workmux,
    vaultMs: spans.vault,
    ioregMs: spans.ioreg,
    selfHealMs: spans.selfHeal,
    paintCount,
    panesPainted,
    refreshCounter,
  };
  for (const span of Object.keys(spans) as Span[]) spans[span] = 0;
  paintCount = 0;
  panesPainted = 0;
  counters.refreshes += 1;
  ring[ringNext] = record;
  ringNext = (ringNext + 1) % RING_SIZE;
  if (record.totalMs > SLOW_REFRESH_MS) {
    // Under sustained load EVERY refresh can be slow; unthrottled lines
    // would outrun the boot-only log rotation. One line per window, with
    // the suppressed count folded into the next one.
    slowSuppressed += 1;
    const now = Date.now();
    if (now - lastSlowLogged >= SLOW_LOG_WINDOW_MS) {
      logLine(`slow refresh x${slowSuppressed} ${JSON.stringify(record)}`);
      lastSlowLogged = now;
      slowSuppressed = 0;
    }
  }
}

// Ring in chronological order, plus the cumulative counters.
export function dump(): string {
  const refreshes =
    ring.length < RING_SIZE
      ? ring
      : [...ring.slice(ringNext), ...ring.slice(0, ringNext)];
  return JSON.stringify({ counters, refreshes });
}
