import assert from "node:assert/strict";
import { execFile, spawn } from "node:child_process";
import crypto from "node:crypto";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { promisify } from "node:util";
import { fileURLToPath } from "node:url";
import test from "node:test";
import {
  assemble,
  build,
} from "../../ai-harness/skills/interactive-plan/scripts/build.mjs";
import {
  artifactData,
  serve,
} from "../../ai-harness/skills/interactive-plan/scripts/session.mjs";

const exec = promisify(execFile);
const root = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "../..",
);
const helper = path.join(
  root,
  "ai-harness/skills/interactive-plan/scripts/session.mjs",
);
const frame = await assemble({
  artifactId: "example",
  revision: "0",
  kind: "exploration",
  title: "Example",
  pages: [{ id: "overview", title: "Overview", html: "" }],
});
function artifact(revision = "1", kind = "exploration") {
  return frame.replace(
    /(<script type="application\/json" id="plan-data">)[\s\S]*?(<\/script>)/,
    `$1${JSON.stringify({ artifactId: "example", revision, kind, title: "Example work", pages: [{ id: "overview", title: "Overview", html: "<p>Preserve one result per input.</p>" }] })}$2`,
  );
}
async function fixture(t) {
  const directory = await fs.mkdtemp(
    path.join(os.tmpdir(), "plan-session-test-"),
  );
  const server = await serve(directory);
  t.after(async () => {
    await server.close();
    await fs.rm(directory, { recursive: true, force: true });
  });
  const connection = JSON.parse(
    await fs.readFile(path.join(directory, "connection.json"), "utf8"),
  );
  const request = async (route, data, headers = {}) => {
    const response = await fetch(server.origin + route, {
      method: data ? "POST" : "GET",
      headers: {
        "Content-Type": "application/json",
        ...(route.startsWith("/agent/")
          ? { authorization: `Bearer ${connection.token}` }
          : { Origin: server.origin }),
        ...headers,
      },
      ...(data ? { body: JSON.stringify(data) } : {}),
    });
    return { code: response.status, body: await response.json() };
  };
  const action = async (action, data = {}) =>
    request("/agent/action", {
      action,
      sessionId: connection.sessionId,
      ...data,
    });
  const event = (intent = "feedback-only", revision = "1", extra = {}) => ({
    sessionId: connection.sessionId,
    artifactId: "example",
    revision,
    intent,
    id: crypto.randomUUID(),
    groups: {},
    text: "Keep the interface.",
    ...extra,
  });
  return { directory, server, connection, request, action, event };
}

test("split authoring sources build a standalone artifact without executing content", async (t) => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), "plan-build-"));
  t.after(() => fs.rm(directory, { recursive: true, force: true }));
  const content = "<h1>Interface</h1><pre>literal </script> and $&</pre>";
  await fs.writeFile(path.join(directory, "interface.html"), content);
  await fs.writeFile(
    path.join(directory, "custom.css"),
    ".prototype { color: var(--attention); }",
  );
  await fs.writeFile(
    path.join(directory, "custom.js"),
    'window.addEventListener("plan:page", () => {});',
  );
  const source = path.join(directory, "source.json");
  await fs.writeFile(
    source,
    JSON.stringify({
      artifactId: "build",
      revision: "1",
      kind: "plan",
      title: "Build",
      css: "custom.css",
      js: "custom.js",
      pages: [{ id: "overview", title: "Overview", file: "interface.html" }],
    }),
  );
  const html = await build(source);
  assert.equal(artifactData(html).pages[0].html, content);
  assert.equal(artifactData(html).pages[0].file, undefined);
  assert.equal(artifactData(html).css, undefined);
  assert(html.includes(".prototype { color: var(--attention); }"));
  assert(html.includes('window.addEventListener("plan:page"'));
  assert(!html.includes("<!-- FRAME_"));
  assert(!html.includes('src="frame.js"'));
  await assert.rejects(
    assemble(artifactData(html), { js: 'const text = "</script>";' }),
    /closing/,
  );
  const output = path.join(directory, "artifact.html");
  const builder = path.join(path.dirname(helper), "build.mjs");
  await exec(process.execPath, [builder, source, output]);
  assert.equal(await fs.readFile(output, "utf8"), html);
  await assert.rejects(
    exec(process.execPath, [builder, source, output]),
    /EEXIST/,
  );
});

test("final review can reopen exploration and only accept the recomposed plan", async (t) => {
  const a = await fixture(t);
  await a.action("publish", { html: artifact("1", "plan") });
  const feedback = a.event();
  await a.request("/api/feedback", feedback);
  await a.action("ack", { id: feedback.id });
  assert.equal(
    (await a.action("publish", { html: artifact("2", "exploration") })).code,
    200,
  );
  assert.equal(
    (
      await a.request(
        "/api/feedback",
        a.event("accept-plan", "1", { mode: "save" }),
      )
    ).code,
    409,
  );
  assert.equal(
    (
      await a.request(
        "/api/feedback",
        a.event("accept-plan", "2", { mode: "save" }),
      )
    ).code,
    409,
  );
  const choice = a.event("feedback-only", "2", {
    text: "Use per-item results.",
  });
  await a.request("/api/feedback", choice);
  await a.action("ack", { id: choice.id });
  await a.action("publish", { html: artifact("3", "plan") });
  const acceptance = a.event("accept-plan", "3", { mode: "save" });
  assert.equal((await a.request("/api/feedback", acceptance)).code, 200);
  await a.action("ack", { id: acceptance.id });
  assert.equal(
    (await a.action("complete")).body.planPath,
    path.join(a.directory, "artifacts/example.3.html"),
  );
  assert.equal(
    artifactData(
      await fs.readFile(
        path.join(a.directory, "artifacts/example.1.html"),
        "utf8",
      ),
    ).kind,
    "plan",
  );
});

test("capability check tests storage and loopback, cleans up, and fails on unusable storage", async (t) => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), "plan-check-"));
  t.after(() => fs.rm(directory, { recursive: true, force: true }));
  const check = path.join(path.dirname(helper), "check.mjs");
  const result = await exec(process.execPath, [check, directory]);
  assert.equal(JSON.parse(result.stdout).ready, true);
  assert.deepEqual(await fs.readdir(directory), []);
  const file = path.join(directory, "not-a-directory");
  await fs.writeFile(file, "preserve");
  await assert.rejects(exec(process.execPath, [check, file]));
  assert.equal(await fs.readFile(file, "utf8"), "preserve");
});

test("artifact parsing requires a real plan overview and preserves rich HTML", () => {
  assert.equal(
    artifactData(artifact("1", "plan")).pages[0].html,
    "<p>Preserve one result per input.</p>",
  );
  assert.throws(
    () => artifactData(artifact().replace('"overview"', '"feedback"')),
    /reserved/,
  );
  assert.throws(
    () =>
      artifactData(artifact("1", "plan").replace('"overview"', '"details"')),
    /overview/,
  );
});

test("two sessions isolate ports, files, events, acknowledgements, and ownership", async (t) => {
  const a = await fixture(t),
    b = await fixture(t);
  assert.notEqual(a.server.origin, b.server.origin);
  assert.notEqual(a.connection.sessionId, b.connection.sessionId);
  assert.equal((await a.action("publish", { html: artifact() })).code, 200);
  assert.equal((await b.action("publish", { html: artifact() })).code, 200);
  const event = a.event();
  assert.equal((await b.request("/api/feedback", event)).code, 409);
  assert.equal((await a.request("/api/feedback", event)).code, 200);
  assert.equal((await b.request("/agent/next")).body.event, null);
  assert.equal((await b.action("ack", { id: event.id })).code, 404);
  assert.equal((await a.action("ack", { id: event.id })).code, 200);
  assert.deepEqual((await b.request("/api/status")).body.acknowledged, []);
  await assert.rejects(serve(a.directory), /already owned/);
  await assert.rejects(serve(a.directory, { recover: true }), /still running/);
  assert.equal(
    (
      await a.request("/api/feedback", a.event(), {
        Origin: "http://example.com",
      })
    ).code,
    403,
  );
  assert.equal(
    (
      await a.request("/agent/next", undefined, {
        authorization: `Bearer ${b.connection.token}`,
      })
    ).code,
    403,
  );
  const html = await (await fetch(a.server.origin)).text();
  assert(html.includes(a.connection.sessionId));
  assert(!html.includes(a.connection.token));
});

test("explicit feedback is retryable, remains unread until ack, and blocks premature publication", async (t) => {
  const a = await fixture(t);
  await a.action("publish", { html: artifact() });
  const event = a.event();
  const receipt = await a.request("/api/feedback", event);
  assert.equal(receipt.body.status.stage, "submitted");
  assert.deepEqual(receipt.body.status.acknowledged, []);
  assert.equal((await a.request("/api/feedback", event)).code, 200);
  assert.equal(
    (await a.request("/api/feedback", { ...event, text: "Changed" })).code,
    409,
  );
  assert.equal((await a.action("publish", { html: artifact("2") })).code, 409);
  const output = JSON.parse(
    (
      await exec(process.execPath, [
        helper,
        "wait",
        "--session-dir",
        a.directory,
        "--timeout",
        "0.2",
      ])
    ).stdout,
  );
  assert.deepEqual(output.event.payload, event);
  await a.action("ack", { id: event.id });
  const acked = (await a.request("/api/status")).body;
  await a.action("ack", { id: event.id });
  assert.equal(
    (await a.request("/api/status")).body.acknowledgedAt,
    acked.acknowledgedAt,
  );
  assert.equal(
    JSON.parse(
      (
        await exec(process.execPath, [
          helper,
          "wait",
          "--session-dir",
          a.directory,
          "--timeout",
          "0.05",
        ])
      ).stdout,
    ).waiting,
    true,
  );
  const original = await fs.readFile(
    path.join(a.directory, "artifacts/example.1.html"),
    "utf8",
  );
  assert.equal((await a.action("publish", { html: artifact("2") })).code, 200);
  assert.equal(
    await fs.readFile(
      path.join(a.directory, "artifacts/example.1.html"),
      "utf8",
    ),
    original,
  );
  assert.equal((await a.request("/api/feedback", a.event())).code, 409);
  assert.equal((await a.action("publish", { html: artifact("2") })).code, 409);
});

test("questions accept a bound browser reply or a terminal resolution, never a stale reply", async (t) => {
  const a = await fixture(t);
  await a.action("publish", { html: artifact() });
  const first = (
    await a.action("question", { text: "Which error representation?" })
  ).body.status.question;
  assert.equal((await a.action("publish", { html: artifact("2") })).code, 409);
  await a.action("working");
  assert.equal(
    (
      await a.request(
        "/api/feedback",
        a.event("clarification-reply", "1", { questionId: first.id }),
      )
    ).code,
    409,
  );
  const second = (await a.action("question", { text: "Typed errors?" })).body
    .status.question;
  const reply = a.event("clarification-reply", "1", {
    questionId: second.id,
    text: "Yes, typed errors.",
  });
  assert.equal((await a.request("/api/feedback", reply)).code, 200);
  assert.equal((await a.request("/api/status")).body.question, null);
  assert.equal(
    (
      await a.request(
        "/api/feedback",
        a.event("clarification-reply", "1", { questionId: second.id }),
      )
    ).code,
    409,
  );
  assert.equal(
    (await a.request("/agent/next")).body.event.payload.text,
    "Yes, typed errors.",
  );
});

test("queued rounds keep receipt order and unrelated feedback does not close a question", async (t) => {
  const a = await fixture(t);
  await a.action("publish", { html: artifact() });
  const question = (await a.action("question", { text: "Which result type?" }))
    .body.status.question;
  const first = a.event(),
    second = a.event();
  await a.request("/api/feedback", first);
  await a.request("/api/feedback", second);
  const unread = (await a.request("/agent/next")).body.event;
  assert.equal(unread.id, first.id);
  await a.action("ack", { id: first.id });
  const next = (await a.request("/agent/next")).body.event;
  assert.equal(next.id, second.id);
  assert.equal(next.sequence, unread.sequence + 1);
  assert.equal((await a.request("/api/status")).body.stage, "needs_reply");
  const reply = a.event("clarification-reply", "1", {
    questionId: question.id,
  });
  assert.equal((await a.request("/api/feedback", reply)).code, 200);
});

for (const mode of ["save", "implement"])
  test(`acceptance records explicit ${mode} mode for the exact final plan`, async (t) => {
    const a = await fixture(t);
    await a.action("publish", { html: artifact() });
    assert.equal(
      (await a.request("/api/feedback", a.event("accept-plan", "1", { mode })))
        .code,
      409,
    );
    await a.action("publish", { html: artifact("2", "plan") });
    assert.equal(
      (await a.request("/api/feedback", a.event("accept-plan", "2"))).code,
      400,
    );
    assert.equal((await a.action("complete")).code, 409);
    const acceptance = a.event("accept-plan", "2", { mode });
    assert.equal((await a.request("/api/feedback", acceptance)).code, 200);
    assert.equal((await a.action("complete")).code, 409);
    await a.action("ack", { id: acceptance.id });
    const complete = (await a.action("complete")).body;
    assert.equal(complete.nextAction, mode);
    assert.equal(
      complete.planPath,
      path.join(a.directory, "artifacts/example.2.html"),
    );
    const record = JSON.parse(
      await fs.readFile(path.join(a.directory, "acceptance.json"), "utf8"),
    );
    assert.equal(record.mode, mode);
    assert.equal(
      record.sha256,
      crypto
        .createHash("sha256")
        .update(await fs.readFile(record.path))
        .digest("hex"),
    );
    await a.action("publish", { html: artifact("3", "plan") });
    assert.equal((await a.action("complete")).code, 409);
    assert.equal((await a.request("/api/status")).body.accepted, null);
  });

test("a crashed helper can explicitly recover its own queue without changing session identity", async (t) => {
  const directory = await fs.mkdtemp(
    path.join(os.tmpdir(), "plan-crash-test-"),
  );
  let child;
  const start = async (recover = false) => {
    child = spawn(
      process.execPath,
      [
        helper,
        "start",
        "--session-dir",
        directory,
        ...(recover ? ["--recover-lock"] : []),
      ],
      { stdio: ["ignore", "pipe", "pipe"] },
    );
    const running = child;
    await new Promise((resolve, reject) => {
      running.stdout.once("data", resolve);
      running.once("error", reject);
      running.once("exit", (code) => reject(Error(`Helper exited ${code}`)));
    });
    return JSON.parse(
      await fs.readFile(path.join(directory, "connection.json"), "utf8"),
    );
  };
  t.after(async () => {
    if (child && child.exitCode === null && !child.killed) {
      const stopped = new Promise((resolve) => child.once("exit", resolve));
      child.kill("SIGTERM");
      await stopped;
    }
    await fs.rm(directory, { recursive: true, force: true });
  });
  const original = await start();
  const response = await fetch(original.origin + "/agent/action", {
    method: "POST",
    headers: {
      authorization: `Bearer ${original.token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      action: "publish",
      sessionId: original.sessionId,
      html: artifact(),
    }),
  });
  assert.equal(response.status, 200);
  const event = {
    sessionId: original.sessionId,
    artifactId: "example",
    revision: "1",
    intent: "feedback-only",
    id: crypto.randomUUID(),
    groups: {},
    text: "Survive a restart",
  };
  await fetch(original.origin + "/api/feedback", {
    method: "POST",
    headers: { Origin: original.origin, "Content-Type": "application/json" },
    body: JSON.stringify(event),
  });
  const stopped = new Promise((resolve) => child.once("exit", resolve));
  child.kill("SIGKILL");
  await stopped;
  const resumed = await start(true);
  assert.equal(resumed.sessionId, original.sessionId);
  assert.notEqual(resumed.token, original.token);
  const result = JSON.parse(
    (
      await exec(process.execPath, [
        helper,
        "wait",
        "--session-dir",
        directory,
        "--timeout",
        "0.2",
      ])
    ).stdout,
  );
  assert.deepEqual(result.event.payload, event);
});
