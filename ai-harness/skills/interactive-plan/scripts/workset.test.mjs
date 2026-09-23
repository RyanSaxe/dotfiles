import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { after, before, test } from "node:test";
import { assemble } from "./build.mjs";
import { artifactData, settings, startHub } from "./session.mjs";
import { declareWorkset, finalData } from "./workset.mjs";

let hub;
let sessionId;
let token;
let sessionDir;
const post = async (route, body, headers = {}) => {
  const response = await fetch(hub.origin + route, {
    method: "POST",
    headers: { "Content-Type": "application/json", ...headers },
    body: JSON.stringify(body),
  });
  return { status: response.status, body: await response.json() };
};
const act = (body) =>
  post(
    `/agent/${sessionId}/action`,
    { ...body, sessionId },
    { authorization: `Bearer ${token}` },
  );
const artifact = {
  artifactId: "workset",
  revision: "1",
  kind: "plan",
  title: "Work set",
  pages: [
    { id: "overview", title: "Overview", html: "<p>Overview</p>" },
    { id: "detail", title: "Detail", html: "<p>Detail</p>" },
  ],
};

test("legacy Agreed pages keep their position in the final snapshot", async () => {
  const legacy = artifactData(
    await assemble({
      ...artifact,
      pages: [
        artifact.pages[0],
        { id: "agreed", title: "Agreed", html: "<p>Legacy agreement</p>" },
      ],
    }),
  );
  const workset = declareWorkset(legacy, "ws-legacy");
  const complete = {
    ...workset,
    declared: workset.declared.map((slot) =>
      slot.id === "agreed"
        ? slot
        : { ...slot, state: "ready", version: "pv-overview" },
    ),
    readyCount: 2,
  };
  const records = new Map(
    complete.declared.map((slot) => [
      slot.id,
      {
        pageId: slot.id,
        title: slot.title,
        html:
          legacy.pages.find((page) => page.id === slot.id)?.html ||
          "<p>missing</p>",
      },
    ]),
  );
  const final = finalData(legacy, complete, records);
  assert.deepEqual(
    final.pages.map((page) => page.id),
    ["overview", "agreed"],
  );
  await assemble(final);
});

before(async () => {
  const home = await fs.mkdtemp(path.join(os.tmpdir(), "plan-workset-"));
  const renderCheck = path.join(home, "render-check.mjs");
  await fs.writeFile(
    renderCheck,
    `import fs from "node:fs/promises";
import path from "node:path";
const file = process.argv[process.argv.indexOf("--file") + 1];
const pageId = process.argv[process.argv.indexOf("--page-id") + 1];
const log = path.join(path.dirname(file), "render.log");
await fs.appendFile(log, "start " + pageId + "\\n");
await new Promise((resolve) => setTimeout(resolve, 100));
await fs.appendFile(log, "end " + pageId + "\\n");
process.exit(2);
`,
    { mode: 0o700 },
  );
  hub = await startHub({
    ...settings({ XDG_STATE_HOME: home, INTERACTIVE_PLAN_PORT: "0" }),
    renderCheck,
    log() {},
  });
  sessionDir = path.join(home, "session");
  const registered = await post(
    "/agent/register",
    { sessionDir, wake: { harness: "codex", thread: "workset-test" } },
    { authorization: `Bearer ${hub.secret}` },
  );
  sessionId = registered.body.sessionId;
  token = JSON.parse(
    await fs.readFile(path.join(sessionDir, "connection.json"), "utf8"),
  ).token;
});
after(() => hub.close());

test("work sets publish immutable pages independently and pin the final snapshot", async () => {
  const started = await act({ action: "start-workset", artifact });
  assert.equal(started.status, 200, JSON.stringify(started.body));
  const worksetId = started.body.workset.id;
  assert.equal(started.body.workset.readyCount, 1);
  assert.equal(started.body.workset.declaredCount, 3);
  assert.equal(
    (await fetch(`${hub.origin}/s/${sessionId}/w/${worksetId}/`)).status,
    200,
  );
  assert.equal(
    (
      await post(
        `/s/${sessionId}/api/feedback`,
        {
          sessionId,
          id: "premature",
          artifactId: "workset",
          revision: "1",
          worksetId,
          intent: "feedback-only",
          groups: {
            choices: {},
            notes: [{ id: "n", topic: "overall", text: "wait" }],
          },
          text: "wait",
        },
        { origin: hub.origin },
      )
    ).status,
    409,
  );

  const [detail, overview] = await Promise.all([
    act({
      action: "publish-page",
      worksetId,
      page: { pageId: "detail", title: "Detail", html: "<p>Detail v1</p>" },
    }),
    act({
      action: "publish-page",
      worksetId,
      page: {
        pageId: "overview",
        title: "Overview",
        html: "<p>Overview v1</p>",
      },
    }),
  ]);
  assert.equal(detail.status, 200, JSON.stringify(detail.body));
  assert.equal(detail.body.page.renderVerified, false);
  assert.ok(detail.body.status.workset.readyCount >= 2);
  const renderLog = await fs.readFile(
    path.join(sessionDir, "worksets", worksetId, "render.log"),
    "utf8",
  );
  assert.deepEqual(
    renderLog
      .trim()
      .split("\n")
      .slice(0, 2)
      .map((line) => line.split(" ")[0]),
    ["start", "start"],
  );
  assert.equal(
    (
      await act({
        action: "publish-page",
        worksetId,
        page: { pageId: "detail", title: "Detail", html: "<p>Detail v2</p>" },
      })
    ).status,
    409,
  );
  assert.equal(
    (
      await act({
        action: "publish-page",
        worksetId,
        page: { pageId: "missing", title: "Missing", html: "<p>x</p>" },
      })
    ).status,
    409,
  );

  assert.equal(detail.body.complete || overview.body.complete, true);
  const finalHtml = await assemble({
    ...artifact,
    revision: "2",
    pages: [
      { id: "overview", title: "Overview", html: "<p>Overview v1</p>" },
      { id: "detail", title: "Detail", html: "<p>Detail v1</p>" },
    ],
  });
  const published = await act({ action: "publish", html: finalHtml });
  assert.equal(published.status, 200, JSON.stringify(published.body));
  assert.equal(published.body.status.current.revision, "2");
  const stored = await fs.readFile(
    path.join(sessionDir, "artifacts", "workset.2.html"),
    "utf8",
  );
  assert.match(stored, /worksetId/);
  assert.match(stored, /pageId.*detail/);
});
