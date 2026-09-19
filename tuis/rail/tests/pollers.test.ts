// Per-source pollers: the churn floor holds under a watcher-event storm,
// content-compare keeps no-op loads from causing renders, the cadence
// switches when intervalMs() changes its answer, and loads are strictly
// single-flight.

import assert from "node:assert/strict";
import { test } from "node:test";

import { makePoller } from "../src/pollers.js";

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

test("50 watcher fires inside the gap cost one extra load (churn floor)", async () => {
  const clock = makeClock();
  const loadsAt: number[] = [];
  const poller = makePoller<number>({
    name: "workmux",
    intervalMs: () => 5000,
    load: () => {
      loadsAt.push(clock.now());
      return Promise.resolve(loadsAt.length);
    },
    changed: () => true,
    onChange: () => {},
    timers: clock.timers,
    now: clock.now,
  });
  await poller.start();
  assert.deepEqual(loadsAt, [0]);
  // Heartbeat churn: 50 watcher events in quick succession.
  await clock.advance(10);
  for (let i = 0; i < 50; i++) poller.trigger(1000);
  await clock.advance(2000);
  // One triggered load at the floor (1s after the last load started),
  // not fifty.
  assert.deepEqual(loadsAt, [0, 1000]);
  // The regular cadence then resumes from the triggered load.
  await clock.advance(5000);
  assert.deepEqual(loadsAt, [0, 1000, 6000]);
  poller.stop();
});

test("content-compare suppresses no-op change callbacks", async () => {
  const clock = makeClock();
  let payload = ["a", "b"];
  const changes: string[][] = [];
  const poller = makePoller<string[]>({
    name: "workmux",
    intervalMs: () => 1000,
    // A NEW array every load — identity always differs, content may not.
    load: () => Promise.resolve([...payload]),
    changed: (previous, next) =>
      JSON.stringify(previous) !== JSON.stringify(next),
    onChange: (next) => changes.push(next),
    timers: clock.timers,
    now: clock.now,
  });
  await poller.start();
  assert.equal(changes.length, 1, "the first load always reports");
  await clock.advance(3000);
  assert.equal(changes.length, 1, "same content, no callbacks");
  payload = ["a", "b", "c"];
  await clock.advance(1000);
  assert.equal(changes.length, 2);
  assert.deepEqual(poller.value(), ["a", "b", "c"]);
  poller.stop();
});

test("the cadence switches when intervalMs changes its answer", async () => {
  const clock = makeClock();
  let interval = 60_000;
  const loadsAt: number[] = [];
  const poller = makePoller<number>({
    name: "vault",
    intervalMs: () => interval,
    load: () => {
      loadsAt.push(clock.now());
      return Promise.resolve(loadsAt.length);
    },
    changed: () => false,
    onChange: () => {},
    timers: clock.timers,
    now: clock.now,
  });
  await poller.start();
  // Slow cadence while the tab is elsewhere.
  await clock.advance(60_000);
  assert.deepEqual(loadsAt, [0, 60_000]);
  // The tab lands on tasks: an early trigger, then the fast cadence.
  interval = 5000;
  poller.trigger(2000);
  await clock.advance(2000);
  assert.deepEqual(loadsAt, [0, 60_000, 62_000]);
  await clock.advance(10_000);
  assert.deepEqual(loadsAt, [0, 60_000, 62_000, 67_000, 72_000]);
  poller.stop();
});

test("loads are single-flight under a slow source", async () => {
  const clock = makeClock();
  let inFlight = 0;
  let started = 0;
  let release: (() => void) | null = null;
  const poller = makePoller<number>({
    name: "slow",
    intervalMs: () => 5000,
    load: () => {
      started += 1;
      inFlight += 1;
      assert.equal(inFlight, 1, "never two loads at once");
      return new Promise<number>((resolve) => {
        release = () => {
          inFlight -= 1;
          resolve(started);
        };
      });
    },
    changed: () => true,
    onChange: () => {},
    timers: clock.timers,
    now: clock.now,
  });
  const first = poller.start();
  await flush();
  assert.equal(started, 1);
  // Triggers landing mid-load do not start a second one...
  poller.trigger(0);
  poller.trigger(0);
  await clock.advance(100);
  assert.equal(started, 1);
  release!();
  await first;
  // ...but the earliest requested due time runs after it completes.
  await clock.advance(0);
  assert.equal(started, 2);
  release!();
  await clock.advance(100);
  assert.equal(started, 2);
  poller.stop();
});

test("a failing load keeps the last value and keeps polling", async () => {
  const clock = makeClock();
  let fail = false;
  const changes: number[] = [];
  let calls = 0;
  const poller = makePoller<number>({
    name: "flaky",
    intervalMs: () => 1000,
    load: () => {
      calls += 1;
      return fail
        ? Promise.reject(new Error("transient"))
        : Promise.resolve(calls);
    },
    changed: (previous, next) => previous !== next,
    onChange: (next) => changes.push(next),
    timers: clock.timers,
    now: clock.now,
  });
  await poller.start();
  assert.equal(poller.value(), 1);
  fail = true;
  await clock.advance(2000);
  assert.equal(calls, 3, "failures do not stop the cadence");
  assert.equal(poller.value(), 1, "the stale value stays painted");
  assert.deepEqual(changes, [1], "failures are not changes");
  fail = false;
  await clock.advance(1000);
  assert.equal(poller.value(), 4);
  assert.deepEqual(changes, [1, 4]);
  poller.stop();
});
