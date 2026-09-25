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
  assert.equal(waiting.track, "still");
  assert.deepEqual(waiting.footer, {
    mark: "queued",
    text: "No agent report yet",
  });
  const sending = run({ current: { revision: "1" } }, { inFlight: true });
  assert.equal(sending.title, "Sending feedback");
  assert.equal(sending.track, "moving");
  assert.equal(sending.footer.mark, "active");
  const acknowledged = run({
    current: { revision: "1" },
    ...read,
    acknowledgedAt: "2026-01-01T00:09:20Z",
  });
  assert.equal(acknowledged.title, "Preparing the next revision");
  assert.deepEqual(acknowledged.slots, []);
  assert.equal(acknowledged.track, "moving");
  assert.deepEqual(acknowledged.footer, {
    mark: "active",
    text: "Agent read your feedback",
    at: "2026-01-01T00:09:20Z",
    late: false,
  });
});

test("published page names keep their order while readiness changes", () => {
  const model = run({
    current: { revision: "2" },
    ...read,
    updatedAt: "2026-01-01T00:09:00Z",
  });
  assert.equal(model.title, "Pages in progress");
  assert.equal(model.summary, "1 of 3 pages ready");
  assert.equal(model.track, null);
  assert.deepEqual(
    model.slots.map((item) => item.id),
    ["agreed", "overview", "detail"],
  );
  assert.deepEqual(model.footer, {
    mark: "active",
    text: "Last report",
    at: "2026-01-01T00:09:00Z",
    late: false,
  });
  const finished = run(
    {
      current: { revision: "2", publishedAt: "2026-01-01T00:08:00Z" },
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
  assert.deepEqual(finished.footer, {
    mark: "complete",
    text: "Finished",
    at: "2026-01-01T00:08:00Z",
  });
});

test("a report older than five minutes turns late and pause or wake failure wins", () => {
  const remote = {
    current: { revision: "2" },
    ...read,
    updatedAt: "2026-01-01T00:05:00Z",
  };
  assert.equal(
    run(remote, { now: Date.parse("2026-01-01T00:09:59Z") }).footer.late,
    false,
  );
  assert.equal(run(remote).footer.late, true);
  assert.equal(run(remote).footer.text, "Last report");
  const paused = run({ ...remote, paused: { reason: "Waiting for input" } });
  assert.equal(paused.stopped, true);
  assert.equal(paused.footer.mark, "stopped");
  assert.match(
    paused.footer.text,
    /Waiting for input\. Send a message in chat/,
  );
  const failed = run({
    ...remote,
    wake: { last: { ok: false } },
    paused: { reason: "Waiting" },
  });
  assert.match(failed.footer.text, /Could not wake the agent/);
  const pausedEarly = run({
    current: { revision: "1" },
    ...read,
    paused: { reason: "Waiting" },
  });
  assert.equal(pausedEarly.track, "still");
});
