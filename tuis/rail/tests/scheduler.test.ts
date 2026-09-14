// The refresh scheduler's one promise: a request landing at ANY instant
// — mid-coalesce, mid-run, at the min-interval ceiling — is followed by
// a refresh. Bursts coalesce, runs never overlap, and a signal storm is
// capped without ever dropping its last signal.

import assert from "node:assert/strict";
import { test } from "node:test";

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

const OPTS = { coalesceMs: 25, minIntervalMs: 50 };

test("a burst of requests coalesces into one trailing-edge run", async () => {
  const clock = makeClock();
  const runsAt: number[] = [];
  const scheduler = makeRefreshScheduler(
    () => {
      runsAt.push(clock.now());
      return Promise.resolve();
    },
    { ...OPTS, timers: clock.timers, now: clock.now },
  );
  scheduler.request("tab");
  scheduler.request("page");
  scheduler.request("%window-add");
  await clock.advance(24);
  assert.deepEqual(runsAt, [], "nothing fires inside the coalesce window");
  await clock.advance(1);
  assert.deepEqual(runsAt, [25]);
  await clock.advance(1000);
  assert.deepEqual(runsAt, [25], "no signal, no run");
  assert.deepEqual(scheduler.reasonCounts(), {
    tab: 1,
    page: 1,
    "%window-add": 1,
  });
  scheduler.stop();
});

test("a request landing mid-run is never dropped (post-run recheck)", async () => {
  const clock = makeClock();
  let finishRun: (() => void) | null = null;
  const runsAt: number[] = [];
  const scheduler = makeRefreshScheduler(
    () => {
      runsAt.push(clock.now());
      return new Promise<void>((resolve) => {
        finishRun = resolve;
      });
    },
    { ...OPTS, timers: clock.timers, now: clock.now },
  );
  scheduler.request("boot");
  await clock.advance(25);
  assert.deepEqual(runsAt, [25]);
  // The refresh is in flight; a signal lands now.
  scheduler.request("mid-run");
  finishRun!();
  // The follow-up honors the min-interval from the first run's START.
  await clock.advance(49);
  assert.deepEqual(runsAt, [25]);
  await clock.advance(1);
  assert.deepEqual(runsAt, [25, 75]);
  finishRun!();
  await clock.advance(1000);
  assert.deepEqual(runsAt, [25, 75], "the recheck fires exactly once");
  scheduler.stop();
});

test("a request during the coalesce window merges without stretching it", async () => {
  const clock = makeClock();
  const runsAt: number[] = [];
  const scheduler = makeRefreshScheduler(
    () => {
      runsAt.push(clock.now());
      return Promise.resolve();
    },
    { ...OPTS, timers: clock.timers, now: clock.now },
  );
  scheduler.request("first");
  await clock.advance(20);
  scheduler.request("second");
  await clock.advance(5);
  // Trailing edge of the FIRST request's window, not the second's.
  assert.deepEqual(runsAt, [25]);
  scheduler.stop();
});

test("a sustained storm is capped at the min interval and drains fully", async () => {
  const clock = makeClock();
  const runsAt: number[] = [];
  const scheduler = makeRefreshScheduler(
    () => {
      runsAt.push(clock.now());
      return Promise.resolve();
    },
    { ...OPTS, timers: clock.timers, now: clock.now },
  );
  // A request every 5ms for a full second: 200 signals.
  for (let at = 0; at < 1000; at += 5) {
    scheduler.request("storm");
    await clock.advance(5);
  }
  // Ceiling: one run per minIntervalMs once saturated.
  assert.ok(
    runsAt.length <= Math.ceil(1000 / OPTS.minIntervalMs) + 1,
    `capped: ${runsAt.length} runs`,
  );
  assert.ok(runsAt.length >= Math.floor(1000 / OPTS.minIntervalMs) - 1);
  for (let i = 1; i < runsAt.length; i++) {
    assert.ok(runsAt[i]! - runsAt[i - 1]! >= OPTS.minIntervalMs);
  }
  // The storm's LAST signal still lands: a final run follows it.
  const lastSignalAt = 995;
  const runs = runsAt.length;
  await clock.advance(100);
  assert.ok(
    runsAt[runsAt.length - 1]! >= lastSignalAt || runsAt.length > runs,
    "the trailing signal got its refresh",
  );
  assert.equal(scheduler.reasonCounts()["storm"], 200);
  scheduler.stop();
});

test("requests after stop are ignored", async () => {
  const clock = makeClock();
  let runs = 0;
  const scheduler = makeRefreshScheduler(
    () => {
      runs += 1;
      return Promise.resolve();
    },
    { ...OPTS, timers: clock.timers, now: clock.now },
  );
  scheduler.request("before");
  scheduler.stop();
  scheduler.request("after");
  await clock.advance(1000);
  assert.equal(runs, 0);
});

test("a rejecting runner does not wedge the loop", async () => {
  const clock = makeClock();
  let runs = 0;
  const scheduler = makeRefreshScheduler(
    () => {
      runs += 1;
      return Promise.reject(new Error("boom"));
    },
    { ...OPTS, timers: clock.timers, now: clock.now },
  );
  scheduler.request("one");
  await clock.advance(25);
  assert.equal(runs, 1);
  scheduler.request("two");
  await clock.advance(50);
  assert.equal(runs, 2, "the scheduler survives a rejected run");
  scheduler.stop();
});

test("startPaused holds every refresh until resume, then fires one", async () => {
  const clock = makeClock();
  let runs = 0;
  const scheduler = makeRefreshScheduler(
    () => {
      runs += 1;
      return Promise.resolve();
    },
    { ...OPTS, startPaused: true, timers: clock.timers, now: clock.now },
  );
  scheduler.request("boot");
  scheduler.request("control-connect");
  await clock.advance(1000);
  assert.equal(runs, 0, "nothing fires while paused");
  scheduler.resume();
  await clock.advance(25);
  assert.equal(runs, 1, "resume fires exactly one coalesced refresh");
  scheduler.stop();
});
