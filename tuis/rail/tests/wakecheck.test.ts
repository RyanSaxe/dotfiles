// The state-file wake policy: which writes in the rail's STATE_DIR wake
// what. Tab switches away from tasks never touch the vault; switching TO
// tasks re-reads it behind a 2s gap; page writes wake a refresh (the old
// daemon slept through them); and the daemon's own output files wake
// nothing — they are written DURING refreshes, and waking on them would
// chain refreshes forever.

import assert from "node:assert/strict";
import { test } from "node:test";

import {
  makePoller,
  stateFileWake,
  VAULT_TAB_TRIGGER_MS,
} from "../src/pollers.js";
import { makeRefreshScheduler } from "../src/scheduler.js";

const flush = (): Promise<void> =>
  new Promise((resolve) => setImmediate(resolve));

interface FakeClock {
  timers: {
    setTimeout(fn: () => void, ms: number): unknown;
    clearTimeout(handle: unknown): void;
  };
  now(): number;
  advance(ms: number): Promise<void>;
}

function makeClock(): FakeClock {
  let nowMs = 0;
  let nextId = 1;
  const queue: { at: number; fn: () => void; id: number }[] = [];
  return {
    timers: {
      setTimeout(fn, ms) {
        const id = nextId++;
        queue.push({ at: nowMs + ms, fn, id });
        return id;
      },
      clearTimeout(handle) {
        const index = queue.findIndex((timer) => timer.id === handle);
        if (index >= 0) queue.splice(index, 1);
      },
    },
    now: () => nowMs,
    async advance(ms: number): Promise<void> {
      const until = nowMs + ms;
      for (;;) {
        await flush();
        queue.sort((a, b) => a.at - b.at || a.id - b.id);
        const next = queue[0];
        if (!next || next.at > until) break;
        nowMs = next.at;
        queue.shift();
        next.fn();
      }
      nowMs = until;
      await flush();
    },
  };
}

test("switching to reviews wakes a refresh but never the vault", () => {
  const wake = stateFileWake("tab", "agents", "reviews");
  assert.equal(wake.refreshReason, "state:tab");
  assert.equal(wake.vaultTriggerMs, null);
});

test("switching TO tasks triggers the vault; staying there does not", () => {
  assert.equal(
    stateFileWake("tab", "agents", "tasks").vaultTriggerMs,
    VAULT_TAB_TRIGGER_MS,
  );
  assert.equal(
    stateFileWake("tab", "reviews", "tasks").vaultTriggerMs,
    VAULT_TAB_TRIGGER_MS,
  );
  // A rewrite of the tab file with the same value (or a page-reset
  // alongside it) is not a switch.
  assert.equal(stateFileWake("tab", "tasks", "tasks").vaultTriggerMs, null);
});

test("enabled and page writes wake refreshes", () => {
  assert.equal(
    stateFileWake("enabled", "agents", "agents").refreshReason,
    "state:enabled",
  );
  assert.equal(
    stateFileWake("page", "agents", "agents").refreshReason,
    "state:page",
  );
});

test("the daemon's own output files wake nothing", () => {
  for (const filename of [
    "hints.tsv",
    "acks.json",
    "attention",
    "attention-pending.json",
    "review-attention",
    "status-stability.json",
    "daemon.pid",
    null,
  ]) {
    const wake = stateFileWake(filename, "agents", "agents");
    assert.equal(wake.refreshReason, null, String(filename));
    assert.equal(wake.vaultTriggerMs, null, String(filename));
  }
});

test("a page write reaches an actual refresh through the scheduler", async () => {
  const clock = makeClock();
  let runs = 0;
  const scheduler = makeRefreshScheduler(
    () => {
      runs += 1;
      return Promise.resolve();
    },
    { coalesceMs: 25, minIntervalMs: 50, timers: clock.timers, now: clock.now },
  );
  const wake = stateFileWake("page", "agents", "agents");
  if (wake.refreshReason !== null) scheduler.request(wake.refreshReason);
  await clock.advance(25);
  assert.equal(runs, 1);
  assert.deepEqual(scheduler.reasonCounts(), { "state:page": 1 });
  scheduler.stop();
});

test("tab bouncing into tasks respects the 2s vault gap end to end", async () => {
  const clock = makeClock();
  const loadsAt: number[] = [];
  const vault = makePoller<number>({
    name: "vault",
    intervalMs: () => 60_000,
    load: () => {
      loadsAt.push(clock.now());
      return Promise.resolve(loadsAt.length);
    },
    changed: () => false,
    onChange: () => {},
    timers: clock.timers,
    now: clock.now,
  });
  await vault.start();
  assert.deepEqual(loadsAt, [0]);

  const visitTasks = (previousTab: string): void => {
    const wake = stateFileWake("tab", previousTab, "tasks");
    if (wake.vaultTriggerMs !== null) vault.trigger(wake.vaultTriggerMs);
  };

  // First visit shortly after boot: the gap defers the read to t=2000.
  await clock.advance(100);
  visitTasks("agents");
  await clock.advance(1900);
  assert.deepEqual(loadsAt, [0, 2000]);
  // Bounce away and back within the gap: still one read per 2s.
  await clock.advance(100);
  visitTasks("reviews");
  await clock.advance(100);
  visitTasks("reviews");
  await clock.advance(5000);
  assert.deepEqual(loadsAt, [0, 2000, 4000]);
  vault.stop();
});
