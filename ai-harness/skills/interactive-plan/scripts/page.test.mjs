import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { promisify } from "node:util";
import { after, before, test } from "node:test";
import { buildPage } from "./build.mjs";
import { pageData, settings, startHub } from "./session.mjs";

let hub, directory, sessionId, token;
const exec = promisify(execFile);
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
const status = async () =>
  (await fetch(`${hub.origin}/s/${sessionId}/api/status`)).json();
const page = async (revision, id, title, html, extra = {}) =>
  buildPage(path.join(directory, "source.json"), {
    artifactId: "page-test",
    revision,
    kind: "plan",
    title: "Page test",
    page: {
      id,
      title,
      ...(id === "agreed"
        ? {
            agreements: [],
            task: { title: "The task", html: "<p>What the plan builds.</p>" },
          }
        : { html }),
      ...extra,
    },
  });
const publish = async (revision, id, title, html, extra, pages) =>
  act({
    action: "publish",
    html: await page(revision, id, title, html, extra),
    ...(pages ? { pages } : {}),
  });
const firstPages = [
  { id: "overview", title: "Overview" },
  { id: "detail", title: "Detail" },
];
const firstAgreements = [
  { id: "alpha", title: "Alpha", html: "<p>Same</p>", source: "Conversation" },
  { id: "beta", title: "Beta", html: "<p>Before</p>", source: "Conversation" },
];

before(async () => {
  const home = await fs.mkdtemp(path.join(os.tmpdir(), "page-round-"));
  hub = await startHub({
    ...settings({ XDG_STATE_HOME: home, INTERACTIVE_PLAN_PORT: "0" }),
    log() {},
    async wake() {},
  });
  directory = path.join(home, "session");
  const registered = await post(
    "/agent/register",
    {
      sessionDir: directory,
      wake: { harness: "codex", thread: "test" },
    },
    { authorization: `Bearer ${hub.secret}` },
  );
  sessionId = registered.body.sessionId;
  token = JSON.parse(
    await fs.readFile(path.join(directory, "connection.json"), "utf8"),
  ).token;
});
after(async () => {
  if (hub) await hub.close();
});

test("Agreed and all page names become visible in one publication", async () => {
  assert.equal((await publish("1", "agreed", "Agreed so far")).status, 400);
  assert.equal((await status()).current, null);
  assert.equal(
    (
      await publish("1", "agreed", "Agreed so far", undefined, {}, [
        firstPages[0],
        firstPages[0],
      ])
    ).status,
    400,
  );
  assert.equal((await status()).current, null);
  const result = await publish(
    "1",
    "agreed",
    "Agreed so far",
    undefined,
    { agreements: firstAgreements },
    firstPages,
  );
  assert.equal(result.status, 200, JSON.stringify(result.body));
  assert.equal(result.body.page.id, "agreed");
  assert.equal((await status()).revisions.length, 0);
  const response = await fetch(`${hub.origin}/s/${sessionId}/`);
  const html = await response.text();
  assert.match(html, /Agreed so far/);
  assert.match(html, /"pageMode":"partial"/);
  assert.match(html, /Detail/);
  const manifest = await (
    await fetch(`${hub.origin}/s/${sessionId}/api/page-set?revision=1`)
  ).json();
  assert.deepEqual(
    manifest.pages.map((item) => item.id),
    ["agreed", "overview", "detail"],
  );
  assert.equal(manifest.pages[1].state, "queued");
  assert.equal(manifest.complete, false);
  assert.equal(
    (
      await act({
        action: "progress",
        pages: [
          { id: "overview", title: "Overview" },
          { id: "overview", title: "Duplicate" },
        ],
      })
    ).status,
    400,
  );
  assert.equal(
    (await publish("1", "detail", "Detail", "<p>x</p>", {}, firstPages)).status,
    400,
  );
  assert.equal(
    (await act({ action: "progress", start: ["missing"] })).status,
    409,
  );
  assert.equal(
    (
      await act({
        action: "publish",
        html: await page("1", "unlisted", "Unlisted", "<p>x</p>"),
      })
    ).status,
    409,
  );
});

test("listed pages arrive independently and only the last completes the revision", async () => {
  assert.equal(
    (await act({ action: "progress", start: ["detail"] })).status,
    200,
  );
  const before = await status();
  assert.equal(before.pageRound.pages[1].state, "active");
  assert.equal(before.needsYou, false);
  const early = await post(
    `/s/${sessionId}/api/feedback`,
    {
      sessionId,
      id: "early",
      artifactId: "page-test",
      revision: "1",
      intent: "feedback-only",
      text: "Too early",
      groups: {},
    },
    { origin: hub.origin },
  );
  assert.equal(early.status, 409);
  const detail = await publish(
    "1",
    "detail",
    "Detail",
    "<p>Finished detail</p>",
  );
  assert.equal(detail.status, 200, JSON.stringify(detail.body));
  assert.equal(detail.body.complete, false);
  const immutable = await fs.readFile(detail.body.page.recordPath, "utf8");
  assert.doesNotMatch(
    await (await fetch(`${hub.origin}/s/${sessionId}/`)).text(),
    /Finished detail/,
  );
  const manifest = await (
    await fetch(`${hub.origin}/s/${sessionId}/api/page-set?revision=1`)
  ).json();
  const slot = manifest.pages.find((item) => item.id === "detail");
  assert.equal(slot.state, "ready");
  const recordResponse = await fetch(
    `${hub.origin}/s/${sessionId}/api/page?revision=1&id=detail&version=${slot.version}`,
  );
  assert.equal(recordResponse.status, 200);
  assert.match((await recordResponse.json()).page.html, /Finished detail/);
  assert.equal(
    (
      await fetch(
        `${hub.origin}/s/${sessionId}/api/page?revision=1&id=detail&version=${"0".repeat(64)}`,
      )
    ).status,
    404,
  );
  const valid = await page(
    "1",
    "overview",
    "Overview",
    "<p>Finished overview</p>",
  );
  const tampered = pageData(valid);
  tampered.page.html = "<h1>Duplicate heading</h1>";
  const failed = await act({
    action: "publish",
    html: valid.replace(
      /(<script type="application\/json" id="page-data">)[\s\S]*?(<\/script>)/,
      (_, start, end) =>
        start + JSON.stringify(tampered).replaceAll("<", "\\u003c") + end,
    ),
  });
  assert.equal(failed.status, 400);
  assert.equal(
    (await status()).current.sha256,
    detail.body.status.current.sha256,
  );
  const artifacts = path.join(directory, "artifacts");
  const held = path.join(directory, "artifacts-held");
  await fs.rename(artifacts, held);
  await fs.writeFile(artifacts, "blocked");
  try {
    const writeFailure = await publish(
      "1",
      "overview",
      "Overview",
      "<p>Finished overview</p>",
    );
    assert.equal(writeFailure.status, 500);
    assert.equal(
      (await status()).current.sha256,
      detail.body.status.current.sha256,
    );
  } finally {
    await fs.unlink(artifacts);
    await fs.rename(held, artifacts);
  }
  const overview = await publish(
    "1",
    "overview",
    "Overview",
    "<p>Finished overview</p>",
  );
  assert.equal(overview.status, 200, JSON.stringify(overview.body));
  assert.equal(overview.body.complete, true);
  assert.equal((await status()).revisions.length, 1);
  assert.equal((await status()).pageRound, null);
  assert.equal((await status()).needsYou, true);
  const completeSet = await (
    await fetch(`${hub.origin}/s/${sessionId}/api/page-set?revision=1`)
  ).json();
  assert.equal(completeSet.complete, true);
  assert.equal(
    (await fetch(`${hub.origin}/s/${sessionId}/api/page-set?revision=missing`))
      .status,
    404,
  );
  assert.equal(
    (
      await fetch(
        `${hub.origin}/s/${sessionId}/api/page?revision=1&id=missing&version=${completeSet.pages[0].version}`,
      )
    ).status,
    404,
  );
  assert.equal(
    await fs.readFile(detail.body.page.recordPath, "utf8"),
    immutable,
  );
  assert.equal(
    (await publish("1", "detail", "Detail", "<p>again</p>")).status,
    409,
  );
});

test("the next revision may choose unrelated pages without changing history", async () => {
  const response = await post(
    `/s/${sessionId}/api/feedback`,
    {
      sessionId,
      id: "feedback-1",
      artifactId: "page-test",
      revision: "1",
      intent: "feedback-only",
      text: "Change topics",
      groups: {
        notes: [
          {
            id: "note-1",
            topic: "detail",
            anchor: "Detail",
            text: "This is agreed.",
          },
        ],
      },
    },
    { origin: hub.origin },
  );
  assert.equal(response.status, 200, JSON.stringify(response.body));
  assert.equal((await act({ action: "read" })).status, 200);
  const agreed = await publish(
    "2",
    "agreed",
    "Agreed so far",
    undefined,
    {
      agreements: [
        { ...firstAgreements[1], html: "<p>After</p>" },
        {
          id: "gamma",
          title: "Gamma",
          html: "<p>New</p>",
          source: "Conversation",
        },
        firstAgreements[0],
        {
          id: "from-detail",
          title: "A settled detail",
          html: "<p>The earlier detail is settled.</p>",
          sourceRefs: [
            { kind: "note", submissionId: "feedback-1", noteId: "note-1" },
          ],
        },
      ],
    },
    [
      { id: "overview", title: "Overview" },
      { id: "new-topic", title: "New topic" },
    ],
  );
  assert.equal(agreed.status, 200, JSON.stringify(agreed.body));
  const source = JSON.parse(
    await fs.readFile(agreed.body.page.recordPath, "utf8"),
  ).page.agreements.find((entry) => entry.id === "from-detail")
    .sourceRecords[0];
  assert.equal(source.revision, "1");
  assert.equal(source.topic, "detail");
  const ordered = JSON.parse(
    await fs.readFile(agreed.body.page.recordPath, "utf8"),
  ).page.agreements.map((entry) => entry.id);
  assert.deepEqual(ordered, ["beta", "gamma", "from-detail", "alpha"]);
  const [one, two] = await Promise.all([
    publish("2", "new-topic", "New topic", "<p>Fresh topic</p>"),
    publish("2", "overview", "Overview", "<p>New overview</p>"),
  ]);
  assert.equal(one.status, 200, JSON.stringify(one.body));
  assert.equal(two.status, 200, JSON.stringify(two.body));
  const old = await (await fetch(`${hub.origin}/s/${sessionId}/r/1`)).text();
  const fresh = await (await fetch(`${hub.origin}/s/${sessionId}/`)).text();
  assert.match(old, /Finished detail/);
  assert.doesNotMatch(fresh, /Finished detail/);
  assert.match(fresh, /Fresh topic/);
  assert.equal((await status()).revisions.length, 2);
  assert.equal(
    (await fetch(`${hub.origin}/s/${sessionId}/api/page-set?revision=1`))
      .status,
    200,
  );
});

test("the CLI builds and publishes each page with its own saved source", async () => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), "page-cli-"));
  const session = path.join(root, "session");
  const registered = await post(
    "/agent/register",
    {
      sessionDir: session,
      wake: { harness: "codex", thread: "test" },
    },
    { authorization: `Bearer ${hub.secret}` },
  );
  const tokenForSession = JSON.parse(
    await fs.readFile(path.join(session, "connection.json"), "utf8"),
  ).token;
  const unsupported = await post(
    `/agent/${registered.body.sessionId}/action`,
    {
      action: "publish",
      sessionId: registered.body.sessionId,
      html: '<script type="application/json" id="session-config">{}</script><script type="application/json" id="plan-data">{}</script>',
    },
    { authorization: `Bearer ${tokenForSession}` },
  );
  assert.equal(unsupported.status, 400);
  assert.match(unsupported.body.error, /page-data/);
  const badAgreed = await buildPage(path.join(root, "bad.json"), {
    artifactId: "cli",
    revision: "1",
    kind: "plan",
    title: "CLI plan",
    page: {
      id: "agreed",
      title: "Agreed so far",
      task: { title: "The task", html: "<p>What the plan builds.</p>" },
      agreements: [
        {
          id: "unsupported",
          title: "Unsupported claim",
          html: "<p>No saved source.</p>",
          sourceRefs: [
            { kind: "note", submissionId: "missing", noteId: "note" },
          ],
        },
      ],
    },
  });
  const rejected = await post(
    `/agent/${registered.body.sessionId}/action`,
    {
      action: "publish",
      sessionId: registered.body.sessionId,
      html: badAgreed,
    },
    { authorization: `Bearer ${tokenForSession}` },
  );
  assert.equal(rejected.status, 400);
  const goodAgreed = await buildPage(path.join(root, "good.json"), {
    artifactId: "cli",
    revision: "1",
    kind: "plan",
    title: "CLI plan",
    page: {
      id: "agreed",
      title: "Agreed so far",
      agreements: [],
      task: { title: "The task", html: "<p>What the plan builds.</p>" },
    },
  });
  const outside = await post(
    `/agent/${registered.body.sessionId}/action`,
    {
      action: "publish",
      sessionId: registered.body.sessionId,
      html: goodAgreed,
      source: "/elsewhere/source",
    },
    { authorization: `Bearer ${tokenForSession}` },
  );
  assert.equal(outside.status, 400);
  assert.equal(
    (
      await (
        await fetch(`${hub.origin}/s/${registered.body.sessionId}/api/status`)
      ).json()
    ).current,
    null,
  );
  const skill = path.dirname(new URL(import.meta.url).pathname);
  const helper = path.join(skill, "session.mjs");
  const builder = path.join(skill, "build.mjs");
  const command = (file, args) => exec(process.execPath, [file, ...args]);
  const agreedSource = path.join(root, "agreed-source");
  await fs.mkdir(agreedSource);
  await fs.writeFile(
    path.join(agreedSource, "agreed.json"),
    JSON.stringify({
      artifactId: "cli",
      revision: "1",
      kind: "plan",
      title: "CLI plan",
      page: {
        id: "agreed",
        title: "Agreed so far",
        agreements: [],
        task: { title: "The task", html: "<p>What the plan builds.</p>" },
      },
    }),
  );
  const agreedHtml = path.join(root, "agreed.html");
  await command(builder, [path.join(agreedSource, "agreed.json"), agreedHtml]);
  const list = path.join(root, "pages.json");
  await fs.writeFile(
    list,
    JSON.stringify({ pages: [{ id: "overview", title: "Overview" }] }),
  );
  await command(helper, [
    "publish",
    "--session-dir",
    session,
    "--file",
    agreedHtml,
    "--pages",
    list,
    "--source",
    agreedSource,
  ]);
  const overviewSource = path.join(root, "overview-source");
  await fs.mkdir(overviewSource);
  await fs.writeFile(
    path.join(overviewSource, "overview.json"),
    JSON.stringify({
      artifactId: "cli",
      revision: "1",
      kind: "plan",
      title: "CLI plan",
      page: { id: "overview", title: "Overview", file: "overview.html" },
    }),
  );
  await fs.writeFile(
    path.join(overviewSource, "overview.html"),
    "<p>Ready by CLI</p>",
  );
  const overviewHtml = path.join(root, "overview-built.html");
  await command(builder, [
    path.join(overviewSource, "overview.json"),
    overviewHtml,
  ]);
  await command(helper, [
    "publish",
    "--session-dir",
    session,
    "--file",
    overviewHtml,
    "--source",
    overviewSource,
  ]);
  assert.match(
    await fs.readFile(
      path.join(session, "src", "1", "overview", "overview.html"),
      "utf8",
    ),
    /Ready by CLI/,
  );
  assert.equal(
    (
      await (
        await fetch(`${hub.origin}/s/${registered.body.sessionId}/api/status`)
      ).json()
    ).revisions.length,
    1,
  );
});

test("an unfinished revision resumes after the hub restarts", async () => {
  const home = await fs.mkdtemp(path.join(os.tmpdir(), "page-restart-"));
  const config = {
    ...settings({ XDG_STATE_HOME: home, INTERACTIVE_PLAN_PORT: "0" }),
    log() {},
  };
  let localHub = await startHub(config);
  const localDir = path.join(config.sessions, "session");
  const call = async (action, body) => {
    const response = await fetch(`${localHub.origin}${action}`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${body.auth}`,
      },
      body: JSON.stringify(body.payload),
    });
    return { status: response.status, body: await response.json() };
  };
  try {
    const joined = await call("/agent/register", {
      auth: localHub.secret,
      payload: {
        sessionDir: localDir,
        wake: { harness: "codex", thread: "test" },
      },
    });
    const id = joined.body.sessionId;
    const secret = JSON.parse(
      await fs.readFile(path.join(localDir, "connection.json"), "utf8"),
    ).token;
    const action = (payload) =>
      call(`/agent/${id}/action`, {
        auth: secret,
        payload: { ...payload, sessionId: id },
      });
    const build = (page) =>
      buildPage(path.join(localDir, "source.json"), {
        artifactId: "restart",
        revision: "1",
        kind: "plan",
        title: "Restart",
        page,
      });
    assert.equal(
      (
        await action({
          action: "publish",
          html: await build({
            id: "agreed",
            title: "Agreed",
            task: { title: "The task", html: "<p>What the plan builds.</p>" },
            agreements: [],
          }),
          pages: [
            { id: "overview", title: "Overview" },
            { id: "detail", title: "Detail" },
          ],
        })
      ).status,
      200,
    );
    assert.equal(
      (
        await action({
          action: "publish",
          html: await build({
            id: "overview",
            title: "Overview",
            html: "<p>First page</p>",
          }),
        })
      ).status,
      200,
    );
    await localHub.close();
    localHub = await startHub(config);
    const statusAfterRestart = await (
      await fetch(`${localHub.origin}/s/${id}/api/status`)
    ).json();
    assert.equal(statusAfterRestart.pageRound.pages[0].state, "ready");
    assert.equal(statusAfterRestart.revisions.length, 0);
    assert.equal(
      (
        await action({
          action: "publish",
          html: await build({
            id: "detail",
            title: "Detail",
            html: "<p>Second page</p>",
          }),
        })
      ).status,
      200,
    );
    assert.equal(
      (await (await fetch(`${localHub.origin}/s/${id}/api/status`)).json())
        .revisions.length,
      1,
    );
  } finally {
    await localHub.close();
  }
});
