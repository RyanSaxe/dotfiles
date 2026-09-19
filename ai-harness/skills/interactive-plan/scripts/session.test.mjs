import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { after, before, test } from "node:test";
import { assemble } from "./build.mjs";
import { detectWake, settings, startHub } from "./session.mjs";

let hub, sessionId, sessionDir, token;
const wakes = [];
let wakeFails = false;
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
    async wake(target, line) {
      wakes.push({ target, line });
      if (wakeFails) throw new Error("thread gone");
    },
  };
  hub = await startHub(config);
  sessionDir = path.join(home, "session");
  const registered = await post(
    "/agent/register",
    { sessionDir, wake: { harness: "codex", thread: "thread-1" } },
    { authorization: `Bearer ${hub.secret}` },
  );
  assert.deepEqual(registered.body.wake, { harness: "codex" });
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

test("declared steps, start, and done marks round-trip through status", async () => {
  assert.ok((await act({ action: "ack", id: "evt1" })).ok);
  assert.equal((await status()).progress, null);
  const declared = await act({
    action: "progress",
    steps: [" Update Agreed ", "Write: P", "Write: Q"],
  });
  assert.ok(declared.ok, JSON.stringify(declared.body));
  assert.deepEqual((await status()).progress.steps, [
    { title: "Update Agreed", state: "pending" },
    { title: "Write: P", state: "pending" },
    { title: "Write: Q", state: "pending" },
  ]);
  const states = async () =>
    (await status()).progress.steps.map((step) => step.state);
  assert.ok(
    (await act({ action: "progress", start: ["Write: P", "Write: Q"] })).ok,
  );
  assert.deepEqual(await states(), ["pending", "active", "active"]);
  assert.ok((await act({ action: "progress", done: "Write: Q" })).ok);
  assert.deepEqual(await states(), ["pending", "active", "done"]);
  assert.ok((await act({ action: "progress", start: ["Write: Q"] })).ok);
  assert.deepEqual(await states(), ["pending", "active", "active"]);
  const unknown = await act({ action: "progress", done: "Nope" });
  assert.equal(unknown.status, 400);
  assert.equal(unknown.body.error, "Unknown progress step");
  assert.equal(
    (await act({ action: "progress", start: ["Write: P", "Nope"] })).status,
    400,
  );
  assert.ok((await act({ action: "progress", steps: ["Again"] })).ok);
  assert.deepEqual(await states(), ["pending"]);
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
  assert.equal(
    (await act({ action: "progress", steps: ["A"], done: "A" })).status,
    400,
  );
});

test("publish clears progress", async () => {
  assert.ok((await act({ action: "publish", html: await artifact("2") })).ok);
  const view = await status();
  assert.equal(view.stage, "updated");
  assert.equal(view.progress, null);
});

const feedback = (id) =>
  post(
    `/s/${sessionId}/api/feedback`,
    {
      sessionId,
      id,
      artifactId: "t",
      revision: "2",
      intent: "feedback-only",
      groups: { choices: {}, notes: [] },
      text: "hi",
    },
    { origin: hub.origin },
  );
// The before hook's submission already woke the agent once, so each test
// waits for its own wake by count and for its result to reach the status.
const settled = async (count) => {
  for (let i = 0; i < 50; i++) {
    const view = await status();
    if (wakes.length === count && view.wake?.last?.at !== settled.seen) {
      settled.seen = view.wake.last.at;
      return view;
    }
    await new Promise((resolve) => setTimeout(resolve, 20));
  }
  throw new Error("the wake was never recorded");
};

test("registration stores the wake target for the agent only", async () => {
  const connection = JSON.parse(
    await fs.readFile(path.join(sessionDir, "connection.json"), "utf8"),
  );
  assert.deepEqual(connection.wake, { harness: "codex" });
  const stored = JSON.parse(
    await fs.readFile(path.join(sessionDir, "wake.json"), "utf8"),
  );
  assert.deepEqual(stored, { harness: "codex", thread: "thread-1" });
  const view = await status();
  assert.equal(view.wake.harness, "codex");
  assert.equal(JSON.stringify(view).includes("thread-1"), false);
  const refused = await post(
    "/agent/register",
    { sessionDir, wake: { harness: "vim" } },
    { authorization: `Bearer ${hub.secret}` },
  );
  assert.equal(refused.status, 400);
});

test("a submission wakes the agent with the line that names the session", async () => {
  assert.equal(wakes.length, 1);
  assert.ok((await feedback("evt2")).ok);
  const view = await settled(2);
  assert.deepEqual(wakes[1].target, { harness: "codex", thread: "thread-1" });
  assert.match(
    wakes[1].line,
    new RegExp(
      `^interactive-plan: feedback arrived on session ${sessionDir} \\(revision 2\\)\\. Run: node .*session\\.mjs wait --session-dir ${sessionDir}$`,
    ),
  );
  assert.equal(view.wake.last.ok, true);
  assert.ok((await act({ action: "ack", id: "evt2" })).ok);
});

test("a failed wake is recorded and the submission stays readable", async () => {
  wakeFails = true;
  assert.ok((await feedback("evt3")).ok);
  const view = await settled(3);
  wakeFails = false;
  assert.equal(view.wake.last.ok, false);
  assert.equal(view.wake.last.reason, "thread gone");
  const next = await fetch(`${hub.origin}/agent/${sessionId}/next`, {
    headers: { authorization: `Bearer ${token}` },
  }).then((response) => response.json());
  assert.equal(next.event.id, "evt3");
  assert.ok((await act({ action: "ack", id: "evt3" })).ok);
});

test("a paused session is not woken until it registers again", async () => {
  const count = wakes.length;
  assert.equal((await act({ action: "pause" })).status, 400);
  assert.ok((await act({ action: "pause", reason: "asked to stop" })).ok);
  assert.equal((await status()).paused.reason, "asked to stop");
  assert.ok((await feedback("evt4")).ok);
  await new Promise((resolve) => setTimeout(resolve, 100));
  assert.equal(wakes.length, count);
  assert.equal(
    (await fetch(`${hub.origin}/api/sessions`).then((r) => r.json()))
      .sessions[0].paused,
    true,
  );
  const again = await post(
    "/agent/register",
    { sessionDir, wake: { harness: "codex", thread: "thread-1" } },
    { authorization: `Bearer ${hub.secret}` },
  );
  assert.ok(again.ok);
  assert.equal((await status()).paused, null);
  assert.ok((await act({ action: "ack", id: "evt4" })).ok);
});

const tools = (chain, port = 4321, sdk = "/sdk/index.js") => ({
  ancestors: () => chain,
  listeningPort: () => port,
  copilotSdk: () => ({ sdk, tried: ["/a/index.js"] }),
});
const claude = {
  CLAUDE_CODE_MESSAGING_SOCKET: "/tmp/cc-socks/1.sock",
  CLAUDE_CODE_MESSAGING_TOKEN: "tok",
};

test("the nearest harness ancestor decides the wake target", () => {
  const env = { ...claude, CODEX_THREAD_ID: "outer" };
  assert.deepEqual(
    detectWake(
      env,
      tools([
        { pid: 2, command: "zsh" },
        { pid: 3, command: "claude" },
        { pid: 4, command: "codex" },
      ]),
    ),
    {
      harness: "claude-code",
      socket: claude.CLAUDE_CODE_MESSAGING_SOCKET,
      token: "tok",
    },
  );
  assert.deepEqual(
    detectWake({ CODEX_THREAD_ID: "t" }, tools([{ pid: 3, command: "codex" }])),
    { harness: "codex", thread: "t" },
  );
  assert.deepEqual(
    detectWake(
      { COPILOT_AGENT_SESSION_ID: "s" },
      tools([{ pid: 3, command: "copilot" }]),
    ),
    { harness: "copilot", sessionId: "s", port: 4321, sdk: "/sdk/index.js" },
  );
  assert.deepEqual(
    detectWake({ CODEX_THREAD_ID: "t" }, tools([{ pid: 2, command: "sh" }])),
    { harness: "codex", thread: "t" },
  );
});

test("start refuses without a wake path and says what to do", () => {
  assert.throws(() => detectWake({}, tools([])), /no wake path/);
  assert.throws(
    () =>
      detectWake(
        { COPILOT_AGENT_SESSION_ID: "s" },
        tools([{ pid: 3, command: "copilot" }], null),
      ),
    /copilot --ui-server --resume s/,
  );
  assert.throws(
    () =>
      detectWake(
        { COPILOT_AGENT_SESSION_ID: "s" },
        tools([{ pid: 3, command: "copilot" }], 4321, null),
      ),
    /SDK was not found at \/a\/index\.js/,
  );
});
