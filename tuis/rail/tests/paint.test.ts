// The paint scheduler's promises: visible panes settle before the refresh
// returns; background fills coalesce latest-frame-wins; two writers never
// interleave on one tty; failures reach onResult exactly once.

import assert from "node:assert/strict";
import { test } from "node:test";

import { fillOrder, makePaintScheduler } from "../src/paint.js";

const flush = (): Promise<void> =>
  new Promise((resolve) => setImmediate(resolve));

interface WriteLog {
  order: string[];
  release(tty: string): void;
}

// A controllable write: each call blocks until released, logging start
// order — enough to observe concurrency and per-pane serialization.
function makeGatedWrite(): {
  write: (tty: string, payload: string) => Promise<boolean>;
  log: WriteLog;
} {
  const order: string[] = [];
  const gates = new Map<string, () => void>();
  return {
    write(tty, payload) {
      order.push(`${tty}:${payload}`);
      return new Promise((resolve) => {
        gates.set(tty, () => resolve(true));
      });
    },
    log: {
      order,
      release(tty) {
        const gate = gates.get(tty);
        gates.delete(tty);
        gate?.();
      },
    },
  };
}

test("visible panes paint concurrently and settle together", async () => {
  const { write, log } = makeGatedWrite();
  const results: string[] = [];
  const painter = makePaintScheduler({
    write,
    onResult: (paneId, _frame, ok) => results.push(`${paneId}:${ok}`),
  });
  let settled = false;
  const visible = painter
    .paintVisible([
      { paneId: "%1", tty: "t1", frame: "A" },
      { paneId: "%2", tty: "t2", frame: "B" },
    ])
    .then(() => {
      settled = true;
    });
  await flush();
  // Both writes started before either finished — concurrent, not serial.
  assert.deepEqual(log.order, ["t1:A", "t2:B"]);
  assert.equal(settled, false);
  log.release("t1");
  log.release("t2");
  await visible;
  assert.deepEqual(results.sort(), ["%1:true", "%2:true"]);
});

test("a queued fill is replaced by a newer frame, not written twice", async () => {
  const { write, log } = makeGatedWrite();
  const painter = makePaintScheduler({
    write,
    onResult: () => {},
    fillConcurrency: 1,
  });
  // Occupy the single drain slot so the queue holds.
  painter.fill([{ paneId: "%1", tty: "t1", frame: "old" }]);
  await flush();
  painter.fill([{ paneId: "%2", tty: "t2", frame: "stale" }]);
  painter.fill([{ paneId: "%2", tty: "t2", frame: "fresh" }]);
  log.release("t1");
  await flush();
  log.release("t2");
  await flush();
  assert.deepEqual(log.order, ["t1:old", "t2:fresh"]);
});

test("a visible paint supersedes the same pane's queued fill", async () => {
  const { write, log } = makeGatedWrite();
  const painter = makePaintScheduler({
    write,
    onResult: () => {},
    fillConcurrency: 1,
  });
  painter.fill([{ paneId: "%1", tty: "t1", frame: "blocker" }]);
  await flush();
  painter.fill([{ paneId: "%2", tty: "t2", frame: "queued" }]);
  const visible = painter.paintVisible([
    { paneId: "%2", tty: "t2", frame: "visible" },
  ]);
  await flush();
  log.release("t2");
  await visible;
  log.release("t1");
  await flush();
  // The queued fill for %2 never ran; only the visible frame did.
  assert.deepEqual(log.order, ["t1:blocker", "t2:visible"]);
});

test("writes to one pane never interleave, across visible and fill", async () => {
  const { write, log } = makeGatedWrite();
  const painter = makePaintScheduler({ write, onResult: () => {} });
  painter.fill([{ paneId: "%1", tty: "t1", frame: "first" }]);
  await flush();
  const visible = painter.paintVisible([
    { paneId: "%1", tty: "t1", frame: "second" },
  ]);
  await flush();
  // Only the first write has started; the visible one chains behind it.
  assert.deepEqual(log.order, ["t1:first"]);
  log.release("t1");
  await flush();
  assert.deepEqual(log.order, ["t1:first", "t1:second"]);
  log.release("t1");
  await visible;
});

test("a rejecting write reports failure instead of wedging the chain", async () => {
  const results: string[] = [];
  const painter = makePaintScheduler({
    write: () => Promise.reject(new Error("boom")),
    onResult: (paneId, _frame, ok) => results.push(`${paneId}:${ok}`),
  });
  await painter.paintVisible([{ paneId: "%1", tty: "t1", frame: "A" }]);
  assert.deepEqual(results, ["%1:false"]);
  assert.equal(painter.pendingCount(), 0);
});

test("fillOrder puts attached sessions before the rest, order-stable", () => {
  const ordered = fillOrder([
    { paneId: "a", sessionAttached: false },
    { paneId: "b", sessionAttached: true },
    { paneId: "c", sessionAttached: false },
    { paneId: "d", sessionAttached: true },
  ]);
  assert.deepEqual(
    ordered.map((t) => t.paneId),
    ["b", "d", "a", "c"],
  );
});
