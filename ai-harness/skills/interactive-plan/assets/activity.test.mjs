import assert from "node:assert/strict";
import { test } from "node:test";
import { activityModel } from "./activity.mjs";

const now = Date.parse("2026-01-01T00:10:00Z");
const submittedRevision = "1";
const currentSet = {
  pages: [
    { id: "agreed", title: "Agreed so far", state: "ready" },
    { id: "overview", title: "Overview", state: "active" },
    { id: "detail", title: "Detail", state: "queued" },
  ],
};
const read = { latestSubmissionId: "s2", lastAcknowledgedId: "s2" };
const run = (remote, extra = {}) =>
  activityModel({ remote, currentSet, submittedRevision, now, ...extra });

test("feedback waits without inventing page names", () => {
  // An acknowledgement from an earlier round does not count for this one.
  const waiting = run({
    current: { revision: "1" },
    latestSubmissionId: "s2",
    lastAcknowledgedId: "s1",
    acknowledgedAt: "2026-01-01T00:01:00Z",
    updatedAt: "2026-01-01T00:02:00Z",
  });
  assert.equal(waiting.title, "Waiting for the agent");
  assert.deepEqual(waiting.slots, []);
  assert.equal(waiting.report, "No agent report yet");
  const sending = run({ current: { revision: "1" } }, { inFlight: true });
  assert.equal(sending.title, "Sending feedback");
  assert.equal(sending.report, "");
  const acknowledged = run({
    current: { revision: "1" },
    ...read,
  });
  assert.equal(acknowledged.title, "Preparing the next revision");
  assert.deepEqual(acknowledged.slots, []);
});

test("published page names keep their order while readiness changes", () => {
  const model = run({
    current: { revision: "2" },
    ...read,
    updatedAt: "2026-01-01T00:09:00Z",
  });
  assert.equal(model.title, "Pages in progress");
  assert.equal(model.summary, "1 of 3 pages ready");
  assert.deepEqual(
    model.slots.map((item) => item.id),
    ["agreed", "overview", "detail"],
  );
  const finished = run(
    {
      current: { revision: "2" },
      ...read,
      updatedAt: "2026-01-01T00:00:00Z",
    },
    {
      currentSet: {
        pages: currentSet.pages.map((item) => ({ ...item, state: "ready" })),
      },
    },
  );
  assert.equal(finished.title, "All pages ready");
  assert.equal(finished.report, "");
});

test("last report waits five minutes and pause or wake failure wins", () => {
  const remote = {
    current: { revision: "2" },
    ...read,
    updatedAt: "2026-01-01T00:05:00Z",
  };
  assert.equal(
    run(remote, { now: Date.parse("2026-01-01T00:09:59Z") }).report,
    "",
  );
  assert.equal(run(remote).report, "stale");
  const paused = run({ ...remote, paused: { reason: "Waiting for input" } });
  assert.equal(paused.stopped, true);
  assert.match(paused.report, /Waiting for input\. Send a message in chat/);
  const failed = run({
    ...remote,
    wake: { last: { ok: false } },
    paused: { reason: "Waiting" },
  });
  assert.match(failed.report, /Could not wake the agent/);
});
