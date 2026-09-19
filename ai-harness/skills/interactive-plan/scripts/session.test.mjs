import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { after, before, test } from "node:test";
import { assemble } from "./build.mjs";
import { settings, startHub } from "./session.mjs";

let hub, sessionId, sessionDir, token;
const artifact = (revision) =>
  assemble({
    artifactId: "t",
    revision,
    kind: "exploration",
    title: "T",
    pages: [{ id: "p", title: "P", html: "<p>x</p>" }],
  });
const post = async (route, body, headers) => {
  const response = await fetch(hub.origin + route, {
    method: "POST",
    headers: { "Content-Type": "application/json", ...headers },
    body: JSON.stringify(body),
  });
  return {
    ok: response.ok,
    status: response.status,
    body: await response.json(),
  };
};
const act = (data) =>
  post(
    `/agent/${sessionId}/action`,
    { ...data, sessionId },
    { authorization: `Bearer ${token}` },
  );
const status = async () =>
  (await fetch(`${hub.origin}/s/${sessionId}/api/status`)).json();

before(async () => {
  const home = await fs.mkdtemp(path.join(os.tmpdir(), "plan-progress-"));
  const config = {
    ...settings({ XDG_STATE_HOME: home, INTERACTIVE_PLAN_PORT: "0" }),
    log() {},
  };
  hub = await startHub(config);
  sessionDir = path.join(home, "session");
  const registered = await post(
    "/agent/register",
    { sessionDir },
    { authorization: `Bearer ${hub.secret}` },
  );
  sessionId = registered.body.sessionId;
  token = JSON.parse(
    await fs.readFile(path.join(sessionDir, "connection.json"), "utf8"),
  ).token;
  assert.ok((await act({ action: "publish", html: await artifact("1") })).ok);
  const feedback = await post(
    `/s/${sessionId}/api/feedback`,
    {
      sessionId,
      id: "evt1",
      artifactId: "t",
      revision: "1",
      intent: "feedback-only",
      groups: { choices: {}, notes: [] },
      text: "hi",
    },
    { origin: hub.origin },
  );
  assert.ok(feedback.ok, JSON.stringify(feedback.body));
});
after(() => hub.close());

test("progress needs an acknowledged round", async () => {
  const result = await act({ action: "progress", steps: ["A"] });
  assert.equal(result.status, 409);
  assert.equal((await status()).progress, null);
});

test("declared steps and done marks round-trip through status", async () => {
  assert.ok((await act({ action: "ack", id: "evt1" })).ok);
  assert.equal((await status()).progress, null);
  const declared = await act({
    action: "progress",
    steps: [" Update Agreed ", "Write: P"],
  });
  assert.ok(declared.ok, JSON.stringify(declared.body));
  assert.deepEqual((await status()).progress.steps, [
    { title: "Update Agreed", done: false },
    { title: "Write: P", done: false },
  ]);
  assert.ok((await act({ action: "progress", done: "Update Agreed" })).ok);
  assert.deepEqual(
    (await status()).progress.steps.map((step) => step.done),
    [true, false],
  );
  const unknown = await act({ action: "progress", done: "Nope" });
  assert.equal(unknown.status, 400);
  assert.equal(unknown.body.error, "Unknown progress step");
});

test("invalid declarations are rejected", async () => {
  assert.equal((await act({ action: "progress", steps: [] })).status, 400);
  assert.equal(
    (await act({ action: "progress", steps: ["A", "A"] })).status,
    400,
  );
  assert.equal(
    (await act({ action: "progress", steps: ["x".repeat(81)] })).status,
    400,
  );
  assert.equal((await act({ action: "progress" })).status, 400);
});

test("publish clears progress", async () => {
  assert.ok((await act({ action: "publish", html: await artifact("2") })).ok);
  const view = await status();
  assert.equal(view.stage, "updated");
  assert.equal(view.progress, null);
});
