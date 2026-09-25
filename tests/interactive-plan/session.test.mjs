import assert from "node:assert/strict";
import { execFile, spawn } from "node:child_process";
import crypto from "node:crypto";
import fs from "node:fs/promises";
import http from "node:http";
import os from "node:os";
import path from "node:path";
import { promisify } from "node:util";
import { fileURLToPath } from "node:url";
import test from "node:test";
import { compareFiles } from "../../ai-harness/skills/interactive-plan/components/before-after/diff.mjs";
import {
  createReviewAlerts,
  reviewAlert,
} from "../../ai-harness/skills/interactive-plan/assets/notifications.mjs";
import {
  emptyDraft,
  loadDraft,
  markSent,
  placeFor,
  readPlaces,
  submissionGroups,
  unsentItems,
} from "../../ai-harness/skills/interactive-plan/assets/draft.mjs";
import {
  assemble,
  build,
  buildPage,
} from "../../ai-harness/skills/interactive-plan/scripts/build.mjs";
import {
  artifactData,
  pageData,
  settings,
  startHub,
  version,
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
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const exists = (file) =>
  fs.access(file).then(
    () => true,
    () => false,
  );
const alive = (pid) => {
  try {
    process.kill(pid, 0);
    return true;
  } catch (error) {
    return error.code !== "ESRCH";
  }
};
// The helper detects the nearest agent process before environment variables.
// Give both supported agent paths dummy targets so a test wake cannot reach
// a real session, including when this suite runs under Codex.
function cliEnv(home, extra = {}) {
  const env = {
    ...process.env,
    XDG_STATE_HOME: home,
    CLAUDE_CODE_MESSAGING_SOCKET: path.join(home, "none.sock"),
    CLAUDE_CODE_MESSAGING_TOKEN: "test",
    CODEX_THREAD_ID: "interactive-plan-test-thread",
    ...extra,
  };
  delete env.COPILOT_AGENT_SESSION_ID;
  return env;
}
async function waitUntil(check, ms = 5000) {
  const deadline = Date.now() + ms;
  while (Date.now() < deadline) {
    if (await check()) return true;
    await sleep(50);
  }
  return false;
}
async function killHub(config) {
  try {
    const record = JSON.parse(await fs.readFile(config.hubFile, "utf8"));
    process.kill(record.pid, "SIGTERM");
    await waitUntil(() => !alive(record.pid), 3000);
  } catch {
    /* No hub record, or the hub already exited. */
  }
}
const sessionConfig = (html) =>
  JSON.parse(html.match(/id="session-config">([\s\S]*?)<\/script>/)[1]);

test("each revision keeps its own remembered place", () => {
  const pages = ["overview", "steps", "feedback"];
  const { tab, past, places } = readPlaces({
    tab: "past",
    past: "1",
    places: {
      1: { page: "steps", top: 640, tops: { steps: 640, overview: 120 } },
      2: { page: "overview", top: "x", tops: { overview: -3 } },
    },
  });
  assert.equal(tab, "past");
  assert.equal(past, "1");
  // Each page read keeps its own scroll position.
  assert.deepEqual(placeFor(places, "1", pages), {
    page: "steps",
    top: 640,
    tops: { steps: 640, overview: 120 },
  });
  assert.deepEqual(placeFor(places, "2", pages), {
    page: "overview",
    top: 0,
    tops: {},
  });
  // A revision never visited opens at its first page.
  assert.equal(placeFor(places, "3", pages), null);
  // A page the revision dropped would land the reader nowhere.
  assert.equal(placeFor(places, "1", ["overview", "feedback"]), null);
  assert.deepEqual(readPlaces(null), {
    tab: "current",
    past: null,
    places: {},
  });
  // A record from before places were kept per revision still counts.
  assert.deepEqual(
    readPlaces({ revision: "2", page: "steps", top: 10 }).places,
    { 2: { page: "steps", top: 10, tops: {} } },
  );
});

test("file comparison preserves exact sources and produces an applicable Git patch", async (t) => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), "plan-diff-"));
  t.after(() => fs.rm(directory, { recursive: true, force: true }));
  const beforePath = path.join(directory, "before.txt");
  const afterPath = path.join(directory, "after.txt");
  const before = "α <tag>\nunchanged\n";
  const after = "α <tag> changed\nunchanged\nno final newline";
  await fs.writeFile(beforePath, before);
  await fs.writeFile(afterPath, after);
  const result = await compareFiles(beforePath, afterPath);
  assert.equal(result.before, before);
  assert.equal(result.after, after);
  assert.ok(result.patch.length > 0);
  const patchPath = path.join(directory, "change.patch");
  await fs.writeFile(patchPath, result.patch);
  await fs.unlink(afterPath);
  const strip =
    path.resolve(directory).split(path.sep).filter(Boolean).length + 1;
  await exec("git", ["apply", `-p${strip}`, patchPath], { cwd: directory });
  assert.equal(await fs.readFile(afterPath, "utf8"), after);
});

test("file comparison distinguishes identical input from a missing input", async (t) => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), "plan-diff-"));
  t.after(() => fs.rm(directory, { recursive: true, force: true }));
  const input = path.join(directory, "input.txt");
  await fs.writeFile(input, "same\r\n");
  const result = await compareFiles(input, input);
  assert.equal(result.patch, "");
  assert.equal(result.before, "same\r\n");
  assert.equal(result.after, "same\r\n");
  await assert.rejects(
    compareFiles(input, path.join(directory, "missing.txt")),
    { code: "ENOENT" },
  );
});

test("drafts carry unsent items across revisions and drop what was sent", () => {
  const draft = emptyDraft("1");
  draft.notes.push({
    id: "n1",
    topic: "overview",
    anchor: "A",
    text: "one",
    revision: "1",
  });
  draft.choices["overview/x"] = {
    topic: "overview",
    label: "X",
    value: "a",
    revision: "1",
  };
  draft.answers["overview/q"] = {
    topic: "overview",
    label: "Q",
    text: "yes",
    revision: "1",
  };
  assert.equal(unsentItems(draft).count, 3);
  assert.deepEqual(Object.keys(submissionGroups(draft)), [
    "alignUnflagged",
    "choices",
    "notes",
    "answers",
  ]);
  markSent(draft, "sub-1", "2000-01-01T00:00:00Z");
  assert.equal(unsentItems(draft).count, 0);
  assert.equal(draft.submitted.count, 3);
  assert.equal(draft.notes[0].sentIn, "sub-1");
  draft.notes.push({
    id: "n2",
    topic: "overview",
    anchor: "B",
    text: "two",
    revision: "1",
  });
  assert.equal(unsentItems(draft).count, 1);
  const groups = submissionGroups(draft);
  assert.deepEqual(
    groups.notes.map((note) => note.id),
    ["n2"],
  );
  assert.equal("sentIn" in groups.notes[0], false);
  assert.equal("answers" in groups, false);
  draft.acceptance = { id: "accept-1", mode: "implement", guidance: "Do this" };
  draft.acceptGuidance = "Do this";
  const same = loadDraft(JSON.parse(JSON.stringify(draft)), "1");
  assert.equal(same.notes.length, 2);
  assert.equal(same.submitted.id, "sub-1");
  assert.equal(same.acceptGuidance, "Do this");
  const next = loadDraft(JSON.parse(JSON.stringify(draft)), "2");
  assert.deepEqual(
    next.notes.map((note) => note.id),
    ["n2"],
  );
  assert.deepEqual(next.choices, {});
  assert.deepEqual(next.answers, {});
  assert.equal(next.submitted, null);
  assert.equal(next.acceptance, null);
  assert.equal(next.acceptGuidance, "");
  assert.equal(next.revision, "2");
  assert.deepEqual(loadDraft(null, "3"), emptyDraft("3"));
  assert.deepEqual(loadDraft({ notes: "bad" }, "3"), emptyDraft("3"));
});

function alertFixture({
  storage = new Map(),
  permission = "default",
  supported = true,
  blockedStorage = false,
  locks,
  sessionId = "s1",
  focused = false,
} = {}) {
  const sent = [],
    opened = [];
  let requests = 0;
  class Notification {
    static permission = permission;
    static async requestPermission() {
      requests++;
      return (this.permission = "granted");
    }
    constructor(title, options) {
      this.title = title;
      this.options = options;
      sent.push(this);
    }
    close() {
      this.closed = true;
    }
  }
  const document = Object.assign(new EventTarget(), {
    hidden: !focused,
    title: "",
    hasFocus: () => focused,
  });
  const host = Object.assign(new EventTarget(), {
    document,
    Notification: supported ? Notification : undefined,
    isSecureContext: true,
    location: { protocol: "http:" },
    navigator: { locks },
    focus() {},
    localStorage: {
      getItem(key) {
        if (blockedStorage) throw Error("blocked");
        return storage.get(key);
      },
      setItem(key, value) {
        if (blockedStorage) throw Error("blocked");
        storage.set(key, value);
      },
    },
  });
  const button = {};
  const alerts = createReviewAlerts({
    window: host,
    button,
    sessionId,
    open: (url) => opened.push(url),
  });
  const entry = (id, revision, extra = {}) => ({
    id,
    title: `Plan ${id}`,
    kind: "exploration",
    revision,
    stage: "updated",
    needsYou: true,
    publishedAt: new Date().toISOString(),
    url: `/s/${id}/`,
    ...extra,
  });
  return {
    alerts,
    host,
    button,
    sent,
    opened,
    entry,
    requests: () => requests,
  };
}
const later = () => new Date(Date.now() + 1000).toISOString();

test("alerts announce other sessions once across tabs and never the focused session", async () => {
  const storage = new Map();
  let queue = Promise.resolve();
  const locks = { request: (_key, callback) => (queue = queue.then(callback)) };
  const a = alertFixture({ storage, locks, sessionId: "s1", focused: true });
  const b = alertFixture({
    storage,
    locks,
    sessionId: "s2",
    permission: "granted",
  });
  await a.button.onclick();
  assert.equal(a.requests(), 1);
  const s1 = a.entry("s1", "2", { publishedAt: later() });
  await Promise.all([a.alerts.update([s1]), b.alerts.update([s1])]);
  assert.equal(a.sent.length + b.sent.length, 0);
  const s3 = a.entry("s3", "1", { publishedAt: later() });
  await Promise.all([a.alerts.update([s1, s3]), b.alerts.update([s1, s3])]);
  assert.equal(a.sent.length + b.sent.length, 1);
  const item = a.sent[0] || b.sent[0];
  assert.equal(item.title, "Revision 1 is ready");
  assert.equal(item.options.body, "Plan s3");
  item.onclick();
  assert.deepEqual([...a.opened, ...b.opened], ["/s/s3/"]);
  await a.alerts.update([s1, s3]);
  assert.equal(a.sent.length + b.sent.length, 1);
  const reload = alertFixture({
    storage,
    locks,
    permission: "granted",
    sessionId: "s2",
  });
  await reload.alerts.update([s1, s3]);
  assert.equal(reload.sent.length, 0);
  const plan = a.entry("s4", "3", { kind: "plan", publishedAt: later() });
  await b.alerts.update([plan]);
  assert.equal(b.sent.at(-1).title, "A final plan is ready");
});

test("granted permission enables automatically unless explicitly disabled; re-enabling skips backlog", async () => {
  const storage = new Map();
  const a = alertFixture({ storage, permission: "granted" });
  await a.alerts.update([a.entry("s2", "1")]);
  assert.equal(a.button.textContent, "Disable notifications");
  assert.equal(a.requests(), 0);
  assert.equal(a.sent.length, 0);
  await a.alerts.update([a.entry("s2", "2", { publishedAt: later() })]);
  assert.equal(a.sent.length, 1);
  await a.button.onclick();
  const b = alertFixture({ storage, permission: "granted" });
  const backlog = b.entry("s2", "3", { publishedAt: later() });
  await b.alerts.update([backlog]);
  assert.equal(b.button.textContent, "Enable notifications");
  assert.equal(b.sent.length, 0);
  await b.button.onclick();
  await b.alerts.update([backlog]);
  assert.equal(b.sent.length, 0);
  await b.alerts.update([
    b.entry("s2", "4", { publishedAt: "2000-01-01T00:00:00Z" }),
  ]);
  assert.equal(b.sent.length, 0);
  await b.alerts.update([
    b.entry("s2", "5", { publishedAt: "2099-01-01T00:00:00Z" }),
  ]);
  assert.equal(b.sent.length, 1);
});

test("only sessions that need the user alert, with the final plan named", () => {
  const entry = {
    id: "s1",
    title: "Plan",
    kind: "plan",
    revision: "3",
    stage: "updated",
    needsYou: true,
    url: "/s/s1/",
    publishedAt: "2026-01-01T00:00:00Z",
  };
  assert.deepEqual(reviewAlert(entry), {
    id: "plan:s1:3",
    sessionId: "s1",
    title: "A final plan is ready",
    body: "Plan",
    url: "/s/s1/",
    createdAt: "2026-01-01T00:00:00Z",
  });
  assert.equal(reviewAlert({ ...entry, needsYou: false }), null);
  assert.equal(reviewAlert({ ...entry, id: "" }), null);
  assert.equal(reviewAlert(null), null);
});

test("denied, unavailable, and failed notifications disable the control", async () => {
  for (const options of [{ permission: "denied" }, { supported: false }]) {
    const a = alertFixture(options);
    await a.alerts.update([a.entry("s2", "1")]);
    assert.equal(a.button.disabled, true);
    assert.equal(a.sent.length, 0);
  }
  const a = alertFixture({ blockedStorage: true });
  await a.button.onclick();
  const entry = a.entry("s2", "1", { publishedAt: later() });
  await a.alerts.update([entry]);
  await a.alerts.update([entry]);
  assert.equal(a.sent.length, 1);
  a.sent[0].onerror();
  assert.equal(a.button.disabled, true);
  assert.match(a.button.title, /delivery failed/);
});

const frame = await assemble({
  artifactId: "example",
  revision: "0",
  kind: "exploration",
  title: "Example",
  pages: [{ id: "overview", title: "Overview", html: "" }],
});
function artifact(
  revision = "1",
  kind = "exploration",
  artifactId = "example",
) {
  return frame.replace(
    /(<script type="application\/json" id="plan-data">)[\s\S]*?(<\/script>)/,
    `$1${JSON.stringify({ artifactId, revision, kind, title: "Example work", pages: [{ id: "overview", title: "Overview", html: "<p>Preserve one result per input.</p>" }] })}$2`,
  );
}
async function hub(t, extra = {}) {
  const home = await fs.mkdtemp(path.join(os.tmpdir(), "plan-hub-"));
  const env = { XDG_STATE_HOME: home, INTERACTIVE_PLAN_PORT: "0", ...extra };
  const config = { ...settings(env), log() {}, async wake() {} };
  const server = await startHub(config);
  t.after(async () => {
    await server.close();
    await killHub(config);
    await fs.rm(home, { recursive: true, force: true });
  });
  const record = JSON.parse(await fs.readFile(config.hubFile, "utf8"));
  async function session(name = crypto.randomUUID()) {
    const directory = path.join(config.sessions, name);
    const registered = await fetch(server.origin + "/agent/register", {
      method: "POST",
      headers: {
        authorization: `Bearer ${record.secret}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        sessionDir: directory,
        wake: { harness: "codex", thread: `thread-${name}` },
      }),
    });
    const info = await registered.json();
    assert.equal(registered.status, 200, info.error);
    const connection = JSON.parse(
      await fs.readFile(path.join(directory, "connection.json"), "utf8"),
    );
    const id = info.sessionId;
    const request = async (route, data, headers = {}) => {
      const response = await fetch(server.origin + route, {
        method: data ? "POST" : "GET",
        redirect: "manual",
        headers: {
          "Content-Type": "application/json",
          ...(route.startsWith("/agent/")
            ? { authorization: `Bearer ${connection.token}` }
            : { Origin: server.origin }),
          ...headers,
        },
        ...(data ? { body: JSON.stringify(data) } : {}),
      });
      const text = await response.text();
      let body;
      try {
        body = JSON.parse(text);
      } catch {
        body = text;
      }
      return { code: response.status, body, headers: response.headers };
    };
    const rawAction = (action, data = {}) =>
      request(`/agent/${id}/action`, { action, sessionId: id, ...data });
    // Most hub tests need a completed revision as setup. Feed the assembled
    // fixture through the page-publication API.
    const action = async (name, data = {}) => {
      if (name !== "publish" || !data.html?.includes('id="plan-data"'))
        return rawAction(name, data);
      let revision;
      try {
        revision = artifactData(data.html);
      } catch {
        return rawAction(name, data);
      }
      const shared = {
        artifactId: revision.artifactId,
        revision: revision.revision,
        kind: revision.kind,
        title: revision.title,
      };
      const source = path.join(directory, "fixture.json");
      const pageHtml = (page) => buildPage(source, { ...shared, page });
      const pages = revision.pages.filter((page) => page.id !== "agreed");
      const prototypes = revision.prototypes || [];
      const ownedBy = (id) =>
        prototypes.filter((prototype) => {
          const owner = pages.find(
            (page) =>
              page.html?.includes(`data-prototype="${prototype.id}"`) ||
              page.html?.includes(`data-prototype='${prototype.id}'`),
          );
          return (owner?.id || "agreed") === id;
        });
      const agreed = await rawAction("publish", {
        html: await pageHtml({
          id: "agreed",
          title: "Agreed so far",
          task: { title: "The task", html: "<p>What the plan builds.</p>" },
          agreements: revision.agreements || [],
          prototypes: ownedBy("agreed"),
        }),
        pages: pages.map(({ id, title }) => ({ id, title })),
        source: data.source,
      });
      if (agreed.code !== 200) return agreed;
      let result = agreed;
      for (const page of pages) {
        result = await rawAction("publish", {
          html: await pageHtml({
            id: page.id,
            title: page.title,
            html: page.html,
            prototypes: ownedBy(page.id),
          }),
          source: data.source,
        });
        if (result.code !== 200) break;
      }
      return result;
    };
    const event = (intent = "feedback-only", revision = "1", extra = {}) => ({
      sessionId: id,
      artifactId: "example",
      revision,
      intent,
      id: crypto.randomUUID(),
      groups: {},
      text: "Keep the interface.",
      ...extra,
    });
    return {
      id,
      base: `/s/${id}`,
      directory,
      info,
      connection,
      request,
      action,
      event,
      feedback: (data, headers) =>
        request(`/s/${id}/api/feedback`, data, headers),
      status: () => request(`/s/${id}/api/status`),
      next: (headers) => request(`/agent/${id}/next`, undefined, headers),
    };
  }
  return {
    home,
    env: { ...process.env, ...env },
    config,
    server,
    record,
    session,
  };
}

test("a page source builds a standalone preview without executing content", async (t) => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), "plan-build-"));
  t.after(() => fs.rm(directory, { recursive: true, force: true }));
  // The frame draws the page title, so the page's own heading is an h2.
  const content =
    '<h2>Interface</h2><pre data-language="text">literal </script> and $&</pre>';
  await fs.writeFile(path.join(directory, "interface.html"), content);
  await fs.writeFile(
    path.join(directory, "custom.css"),
    ".prototype { color: var(--attention); }",
  );
  await fs.writeFile(
    path.join(directory, "custom.js"),
    'export function setup(root) { root.dataset.test = "ready"; }',
  );
  const source = path.join(directory, "source.json");
  await fs.writeFile(
    source,
    JSON.stringify({
      artifactId: "build",
      revision: "1",
      kind: "plan",
      title: "Build",
      page: {
        id: "overview",
        title: "Overview",
        file: "interface.html",
        css: "custom.css",
        js: "custom.js",
      },
    }),
  );
  const html = await build(source);
  assert.equal(pageData(html).page.html, content);
  assert.equal(pageData(html).page.file, undefined);
  assert.equal(
    pageData(html).page.cssText,
    ".prototype { color: var(--attention); }",
  );
  assert.equal(
    pageData(html).page.jsText,
    'export function setup(root) { root.dataset.test = "ready"; }',
  );
  assert(html.includes(".prototype { color: var(--attention); }"));
  assert(html.includes("export function loadDraft"));
  assert(!html.includes("<!-- FRAME_"));
  assert(!html.includes('src="frame.js"'));
  const output = path.join(directory, "artifact.html");
  const builder = path.join(path.dirname(helper), "build.mjs");
  await exec(process.execPath, [builder, source, output]);
  assert.equal(await fs.readFile(output, "utf8"), html);
  await assert.rejects(
    exec(process.execPath, [builder, source, output]),
    /EEXIST/,
  );

  // The skill is installed through a symlink; the builder must still know
  // it is the script being run.
  const link = path.join(directory, "skill");
  await fs.symlink(path.dirname(path.dirname(helper)), link);
  const linked = path.join(directory, "linked.html");
  await exec(process.execPath, [
    path.join(link, "scripts", "build.mjs"),
    source,
    linked,
  ]);
  assert.equal(await fs.readFile(linked, "utf8"), html);
  await assert.rejects(
    exec(process.execPath, [path.join(link, "scripts", "build.mjs")]),
    /Usage/,
  );
});

test("preserved prototypes retain exact executable source without escaping into the frame", async (t) => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), "plan-prototype-"));
  t.after(() => fs.rm(directory, { recursive: true, force: true }));
  const html =
    '<!doctype html><button id="try">Try</button><script>document.querySelector("button").onclick = () => alert("$&");</script>';
  await fs.writeFile(path.join(directory, "prototype.html"), html);
  const data = {
    artifactId: "example",
    revision: "1",
    kind: "exploration",
    title: "Example work",
    page: {
      id: "overview",
      title: "Preview",
      html: '<div data-prototype="demo"></div><code>data-prototype="ID"</code>',
      prototypes: [
        {
          id: "demo",
          title: "Approved interaction",
          file: "prototype.html",
          height: 420,
        },
      ],
    },
  };
  const source = path.join(directory, "source.json");
  await fs.writeFile(source, JSON.stringify(data));
  const result = await build(source);
  const parsed = pageData(result);
  assert.equal(parsed.page.prototypes[0].html, html);
  assert.equal(parsed.page.prototypes[0].file, undefined);
  assert(!result.includes(html));
  for (const prototypes of [
    [],
    [null],
    [{ ...parsed.page.prototypes[0], height: 0 }],
    [{ ...parsed.page.prototypes[0], html: "" }],
    [parsed.page.prototypes[0], parsed.page.prototypes[0]],
  ])
    await assert.rejects(
      buildPage(source, { ...parsed, page: { ...parsed.page, prototypes } }),
    );
  await fs.writeFile(
    source,
    JSON.stringify({
      ...data,
      page: {
        ...data.page,
        prototypes: [{ ...data.page.prototypes[0], html }],
      },
    }),
  );
  await assert.rejects(build(source), /file.*html|html.*file/);
});

test("publication resolves exact mixed sources from saved feedback before hashing", async (t) => {
  const h = await hub(t);
  const a = await h.session();
  await a.action("publish", { html: artifact() });
  const feedback = a.event("feedback-only", "1", {
    groups: {
      notes: [
        {
          id: "note-1",
          topic: "overview",
          anchor: "Failure handling",
          text: "Keep <strong>literal</strong> and </script> $&",
          quote: "A failed item",
          target: "failure",
        },
      ],
      choices: {
        "overview:errors": {
          topic: "overview",
          label: "Error policy",
          value: "per-item",
          target: "errors",
        },
      },
    },
  });
  assert.equal((await a.feedback(feedback)).code, 200);
  await a.action("read");
  const entry = {
    id: "errors",
    title: "Per-item errors",
    html: "<p>Keep successful results.</p>",
    sourceRefs: [
      { kind: "note", submissionId: feedback.id, noteId: "note-1" },
      {
        kind: "choice",
        submissionId: feedback.id,
        choiceId: "overview:errors",
      },
      {
        kind: "conversation",
        text: "Driver also confirmed the return type in conversation.",
      },
    ],
    sourceRecords: [{ kind: "note", text: "Forged source" }],
  };
  const data = { ...artifactData(artifact("2")), agreements: [entry] };
  const result = await a.action("publish", { html: await assemble(data) });
  assert.equal(result.code, 200);
  const snapshot = await fs.readFile(
    path.join(a.directory, "artifacts/example.2.html"),
    "utf8",
  );
  const records = artifactData(snapshot).agreements[0].sourceRecords;
  assert.equal(records.length, 3);
  assert.equal(records[0].text, feedback.groups.notes[0].text);
  assert.equal(records[0].quote, "A failed item");
  assert.equal(records[0].target, "failure");
  assert.equal(records[0].href, "./example.1.html?target=failure#overview");
  assert.equal(records[1].text, "per-item");
  assert.equal(records[1].label, "Error policy");
  assert.equal(records[1].href, "./example.1.html?target=errors#overview");
  assert.deepEqual(records[2], entry.sourceRefs[2]);
  assert(!snapshot.includes(feedback.groups.notes[0].text));
  assert.equal(
    result.body.status.current.sha256,
    crypto.createHash("sha256").update(snapshot).digest("hex"),
  );
  await a.feedback(a.event("feedback-only", "2"));
  await a.action("read");
  for (const ref of [
    { kind: "note", submissionId: "missing", noteId: "note-1" },
    { kind: "note", submissionId: feedback.id, noteId: "missing" },
    { kind: "choice", submissionId: feedback.id, choiceId: "missing" },
  ]) {
    const rejected = await a.action("publish", {
      html: await assemble({
        ...data,
        revision: "3",
        agreements: [{ ...entry, sourceRefs: [ref] }],
      }),
    });
    assert.equal(rejected.code, 400);
    assert.match(rejected.body.error, /Source .*not found/);
  }
  for (const sourceRefs of [
    [],
    [{ kind: "unknown" }],
    [{ kind: "conversation", text: "" }],
    [{ kind: "note", submissionId: feedback.id }],
    [{ kind: "answer", submissionId: feedback.id }],
  ])
    await assert.rejects(
      assemble({ ...data, agreements: [{ ...entry, sourceRefs }] }),
    );
});

test("choice sources preserve readable labels and complete checklist snapshots", async (t) => {
  const h = await hub(t);
  const a = await h.session();
  await a.action("publish", { html: artifact() });
  const choices = {
    "overview/policy": {
      topic: "overview",
      label: "Error policy",
      value: "per-item",
      valueLabel: "Keep successful results",
      target: "policy",
    },
    "overview/scope": {
      kind: "multiple",
      topic: "overview",
      label: "Scope",
      target: "scope",
      options: [
        { value: "labels", label: "Readable <labels>", checked: true },
        { value: "drafts", label: "Draft visibility", checked: false },
      ],
    },
    "overview/empty": {
      kind: "multiple",
      topic: "overview",
      label: "Optional work",
      target: "optional",
      options: [{ value: "extra", label: "Extra work", checked: false }],
    },
  };
  const feedback = a.event("feedback-only", "1", { groups: { choices } });
  assert.equal((await a.feedback(feedback)).code, 200);
  await a.action("read");
  const data = {
    ...artifactData(artifact("2")),
    agreements: [
      {
        id: "scope",
        title: "Scope",
        html: "<p>Preserve the selected work.</p>",
        sourceRefs: Object.keys(choices).map((choiceId) => ({
          kind: "choice",
          submissionId: feedback.id,
          choiceId,
        })),
      },
    ],
  };
  const published = await a.action("publish", { html: await assemble(data) });
  assert.equal(published.code, 200);
  const html = await fs.readFile(
    path.join(a.directory, "artifacts/example.2.html"),
    "utf8",
  );
  const sources = artifactData(html).agreements[0].sourceRecords;
  assert.deepEqual(
    sources.map((source) => source.choice),
    Object.values(choices),
  );
  assert.deepEqual(
    sources.map((source) => source.text),
    ["Keep successful results", "Readable <labels>", "None selected"],
  );
  assert.equal(sources[1].href, "./example.1.html?target=scope#overview");
  assert(!html.includes("Readable <labels>"));
});

test("answers travel with feedback and resolve as agreement sources", async (t) => {
  const h = await hub(t);
  const a = await h.session();
  await a.action("publish", { html: artifact() });
  for (const answers of [
    [],
    { "overview/q1": { label: "Sidebar?", topic: "overview" } },
    { "overview/q1": { label: "Sidebar?", topic: "overview", text: "  " } },
    { "overview/q1": null },
  ]) {
    const rejected = await a.feedback(
      a.event("feedback-only", "1", { groups: { answers } }),
    );
    assert.equal(rejected.code, 400);
  }
  const feedback = a.event("feedback-only", "1", {
    groups: {
      answers: {
        "overview/q1": {
          label: "Sidebar?",
          text: "Yes, keep the <sidebar>",
          topic: "overview",
          target: "question-overview-0",
        },
      },
    },
  });
  assert.equal((await a.feedback(feedback)).code, 200);
  const received = await a.next();
  assert.deepEqual(
    received.body.event.payload.groups.answers,
    feedback.groups.answers,
  );
  await a.action("read");
  const entry = {
    id: "sidebar",
    title: "Keep the sidebar",
    html: "<p>Pages stay in the sidebar.</p>",
    sourceRefs: [
      { kind: "answer", submissionId: feedback.id, answerId: "overview/q1" },
    ],
  };
  const published = await a.action("publish", {
    html: await assemble({
      ...artifactData(artifact("2")),
      agreements: [entry],
    }),
  });
  assert.equal(published.code, 200, published.body.error);
  const html = await fs.readFile(
    path.join(a.directory, "artifacts/example.2.html"),
    "utf8",
  );
  const [record] = artifactData(html).agreements[0].sourceRecords;
  assert.equal(record.kind, "answer");
  assert.equal(record.text, "Yes, keep the <sidebar>");
  assert.equal(record.label, "Sidebar?");
  assert.equal(record.target, "question-overview-0");
  assert.equal(
    record.href,
    "./example.1.html?target=question-overview-0#overview",
  );
  assert(!html.includes("Yes, keep the <sidebar>"));
  await a.feedback(a.event("feedback-only", "2"));
  await a.action("read");
  const missing = await a.action("publish", {
    html: await assemble({
      ...artifactData(artifact("3")),
      agreements: [
        {
          ...entry,
          sourceRefs: [
            { kind: "answer", submissionId: feedback.id, answerId: "nope" },
          ],
        },
      ],
    }),
  });
  assert.equal(missing.code, 400);
  assert.match(missing.body.error, /Source item not found/);
});

test("final review can reopen exploration and only accept the recomposed plan", async (t) => {
  const h = await hub(t);
  const a = await h.session();
  await a.action("publish", { html: artifact("1", "plan") });
  const feedback = a.event();
  await a.feedback(feedback);
  await a.action("read");
  assert.equal(
    (await a.action("publish", { html: artifact("2", "exploration") })).code,
    200,
  );
  assert.equal(
    (await a.feedback(a.event("accept-plan", "1", { mode: "save" }))).code,
    409,
  );
  assert.equal(
    (await a.feedback(a.event("accept-plan", "2", { mode: "save" }))).code,
    409,
  );
  const choice = a.event("feedback-only", "2", {
    text: "Use per-item results.",
  });
  await a.feedback(choice);
  await a.action("read");
  await a.action("publish", { html: artifact("3", "plan") });
  const acceptance = a.event("accept-plan", "3", { mode: "save" });
  assert.equal((await a.feedback(acceptance)).code, 200);
  await a.action("read");
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

test("agreement authoring preserves rich content and rejects ambiguous records", async (t) => {
  const data = artifactData(artifact());
  const entry = {
    id: "errors",
    title: "Per-item errors",
    html: "<pre>Result[Prediction, Error]</pre>",
    source: "User selected per-item errors",
    href: "./example.1.html?target=errors#overview",
  };
  const parsed = artifactData(await assemble({ ...data, agreements: [entry] }));
  assert.deepEqual(parsed.agreements, [entry]);
  for (const agreements of [
    [entry, entry],
    [{ ...entry, id: "bad id" }],
    [{ ...entry, state: "pending" }],
    [{ ...entry, change: "old" }],
    [{ ...entry, source: "" }],
    [{ ...entry, href: "javascript:alert(1)" }],
    [{ ...entry, href: "data:text/html,test" }],
    null,
  ])
    await assert.rejects(assemble({ ...data, agreements }));
  const duplicateAgreed = {
    ...data,
    pages: [
      ...data.pages,
      { id: "agreed", title: "Agreed", html: "Previous decision" },
    ],
  };
  await assert.rejects(assemble({ ...duplicateAgreed, agreements: [] }));
  const directory = await fs.mkdtemp(
    path.join(os.tmpdir(), "agreement-build-"),
  );
  t.after(() => fs.rm(directory, { recursive: true, force: true }));
  await fs.writeFile(path.join(directory, "decision.html"), entry.html);
  const { html, ...metadata } = entry;
  const source = path.join(directory, "source.json");
  await fs.writeFile(
    source,
    JSON.stringify({
      artifactId: data.artifactId,
      revision: data.revision,
      kind: data.kind,
      title: data.title,
      page: {
        id: "agreed",
        title: "Agreed so far",
        task: { title: "The task", html: "<p>What the plan builds.</p>" },
        agreements: [{ ...metadata, file: "decision.html" }],
      },
    }),
  );
  assert.equal(pageData(await build(source)).page.agreements[0].html, html);
});

test("agreements survive topic changes and targeted feedback without rewriting snapshots", async (t) => {
  const h = await hub(t);
  const a = await h.session();
  const entry = {
    id: "errors",
    title: "Per-item errors",
    html: "<p>Keep each error.</p>",
    source: "User's answer",
  };
  const states = ["agreed", "reopened", "agreed", "retired"];
  for (const [index, state] of states.entries()) {
    const revision = String(index + 1);
    const data = {
      ...artifactData(artifact(revision)),
      pages: [
        {
          id: `topic-${revision}`,
          title: `Topic ${revision}`,
          html: "<p>Current proposal</p>",
        },
      ],
      agreements: [{ ...entry, state }],
    };
    assert.equal(
      (await a.action("publish", { html: await assemble(data) })).code,
      200,
    );
    const event = a.event("feedback-only", revision, {
      groups: {
        notes: [
          {
            id: crypto.randomUUID(),
            topic: "agreed",
            agreementId: entry.id,
            anchor: entry.title,
            revision,
            text: "Reconsider the error type.",
          },
        ],
      },
    });
    assert.equal((await a.feedback(event)).code, 200);
    const received = await a.next();
    assert.equal(
      received.body.event.payload.groups.notes[0].agreementId,
      entry.id,
    );
    assert.equal(received.body.event.payload.intent, "feedback-only");
    await a.action("read");
  }
  for (const [index, state] of states.entries()) {
    const snapshot = artifactData(
      await fs.readFile(
        path.join(a.directory, `artifacts/example.${index + 1}.html`),
        "utf8",
      ),
    );
    assert.equal(snapshot.agreements[0].state, state);
    assert.equal(snapshot.agreements[0].id, entry.id);
  }
  const status = (await a.status()).body;
  assert.deepEqual(
    status.revisions.map((item) => item.revision),
    ["1", "2", "3", "4"],
  );
  assert.equal(status.revisions[0].url, `${a.base}/r/1`);
});

test("capability check tests storage, loopback, and the hub port, then cleans up", async (t) => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), "plan-check-"));
  t.after(() => fs.rm(directory, { recursive: true, force: true }));
  const check = path.join(path.dirname(helper), "check.mjs");
  const result = await exec(process.execPath, [check, directory], {
    env: { ...process.env, INTERACTIVE_PLAN_PORT: "0" },
  });
  const report = JSON.parse(result.stdout);
  assert.equal(report.ready, true);
  assert.equal(report.hub.state, "os-assigned");
  assert.deepEqual(await fs.readdir(directory), []);
  const h = await hub(t);
  const live = JSON.parse(
    (
      await exec(process.execPath, [check, directory], {
        env: { ...process.env, INTERACTIVE_PLAN_PORT: String(h.record.port) },
      })
    ).stdout,
  );
  assert.equal(live.hub.state, "hub");
  assert.equal(live.hub.version, version);
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

test("two sessions on one hub isolate tokens, events, and acknowledgements", async (t) => {
  const h = await hub(t);
  const a = await h.session(),
    b = await h.session();
  assert.notEqual(a.id, b.id);
  assert.notEqual(a.connection.token, b.connection.token);
  assert.equal(a.connection.origin, h.server.origin);
  assert.equal(a.info.url, `${h.server.origin}${a.base}/`);
  assert.equal((await a.action("publish", { html: artifact() })).code, 200);
  assert.equal((await b.action("publish", { html: artifact() })).code, 200);
  const event = a.event();
  assert.equal((await b.feedback(event)).code, 409);
  assert.equal((await a.feedback(event)).code, 200);
  assert.equal((await b.next()).body.event, null);
  assert.equal((await b.action("read", { id: event.id })).code, 404);
  assert.equal((await a.action("read")).body.event.id, event.id);
  assert.deepEqual((await b.status()).body.acknowledged, []);
  assert.equal(
    (await a.feedback(a.event(), { Origin: "http://example.com" })).code,
    403,
  );
  assert.equal(
    (
      await a.next({
        authorization: `Bearer ${b.connection.token}`,
      })
    ).code,
    403,
  );
  assert.equal(
    (await a.request(`/agent/${a.id}/next`, undefined, { authorization: "" }))
      .code,
    403,
  );
  const html = (await a.request(`${a.base}/`)).body;
  assert(html.includes(a.id));
  assert(!html.includes(a.connection.token));
  assert(!html.includes(h.record.secret));
  assert.equal((await a.request("/s/unknown/")).code, 404);
  assert.equal(
    (await a.request("/agent/register", { sessionDir: a.directory })).code,
    403,
  );
  const listed = (await a.request("/api/sessions")).body.sessions;
  assert.deepEqual(listed.map((item) => item.id).sort(), [a.id, b.id].sort());
});

test("the hub lists open sessions needs-you first, and a paused one stays listed as paused", async (t) => {
  const h = await hub(t);
  const a = await h.session(),
    b = await h.session();
  await h.session();
  await a.action("publish", { html: artifact() });
  await sleep(5);
  await b.action("publish", { html: artifact() });
  let list = (await a.request("/api/sessions")).body.sessions;
  assert.deepEqual(
    list.map((item) => item.id),
    [a.id, b.id],
  );
  const feedback = b.event();
  await b.feedback(feedback);
  await b.action("read");
  list = (await a.request("/api/sessions")).body.sessions;
  assert.deepEqual(
    list.map((item) => [item.id, item.needsYou, item.stage]),
    [
      [a.id, true, "updated"],
      [b.id, false, "working"],
    ],
  );
  await b.action("publish", { html: artifact("2") });
  const first = a.event();
  await a.feedback(first);
  await a.action("read");
  list = (await a.request("/api/sessions")).body.sessions;
  assert.deepEqual(
    list.map((item) => item.id),
    [b.id, a.id],
  );
  assert.equal(list[0].revision, "2");
  assert.equal(
    (await b.action("pause", { reason: "asked to stop" })).code,
    200,
  );
  assert.equal((await b.status()).body.paused.reason, "asked to stop");
  list = (await a.request("/api/sessions")).body.sessions;
  assert.deepEqual(
    list.map((item) => [item.id, item.paused]),
    [
      [b.id, true],
      [a.id, false],
    ],
  );
  assert.equal((await b.request(`${b.base}/`)).code, 200);
  const again = await fetch(h.server.origin + "/agent/register", {
    method: "POST",
    headers: {
      authorization: `Bearer ${h.record.secret}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      sessionDir: b.directory,
      wake: { harness: "codex", thread: "thread-again" },
    }),
  });
  assert.equal(again.status, 200);
  assert.equal((await b.status()).body.paused, null);
});

test("closing a session from the bell panel completes it and drops it from the list", async (t) => {
  const h = await hub(t);
  const a = await h.session(),
    b = await h.session();
  await a.action("publish", { html: artifact() });
  await b.action("publish", { html: artifact() });
  assert.equal(
    (await b.request(`${b.base}/api/dismiss`, {}, { Origin: "http://evil" }))
      .code,
    403,
  );
  const dismissed = await b.request(`${b.base}/api/dismiss`, {});
  assert.equal(dismissed.code, 200);
  assert.equal(dismissed.body.status.stage, "complete");
  const status = (await b.status()).body;
  assert.equal(status.stage, "complete");
  assert.equal(typeof status.dismissedAt, "string");
  const list = (await a.request("/api/sessions")).body.sessions;
  assert.deepEqual(
    list.map((item) => item.id),
    [a.id],
  );
  // The closed session's own page comes back read-only, so a tab still
  // open on it cannot send anything.
  assert.deepEqual(sessionConfig((await b.request(`${b.base}/`)).body), {
    sessionId: b.id,
    base: b.base,
    closed: true,
  });
  assert.deepEqual(sessionConfig((await a.request(`${a.base}/`)).body), {
    sessionId: a.id,
    base: a.base,
  });
});

test("the root URL opens the session that most needs you, then the last viewed, else says so", async (t) => {
  const h = await hub(t);
  const open = async (cookie) => {
    const response = await fetch(h.server.origin + "/", {
      redirect: "manual",
      headers: cookie ? { cookie } : {},
    });
    return {
      code: response.status,
      location: response.headers.get("location"),
      text: await response.text(),
    };
  };
  let result = await open();
  assert.equal(result.code, 200);
  assert.match(result.text, /No live sessions/);
  const a = await h.session(),
    b = await h.session();
  await b.action("publish", { html: artifact() });
  await sleep(5);
  await a.action("publish", { html: artifact() });
  result = await open();
  assert.equal(result.code, 302);
  assert.equal(result.location, `${b.base}/`);
  for (const session of [a, b]) {
    const event = session.event();
    await session.feedback(event);
    await session.action("read");
  }
  assert.equal(
    (await open(`interactive-plan-last=${a.id}`)).location,
    `${a.base}/`,
  );
  assert.equal(
    (await open(`interactive-plan-last=nope`)).location,
    `${b.base}/`,
  );
  const page = await fetch(h.server.origin + `${a.base}/`);
  assert.match(
    page.headers.get("set-cookie"),
    new RegExp(`interactive-plan-last=${a.id}`),
  );
  const bare = await fetch(h.server.origin + a.base, { redirect: "manual" });
  assert.equal(bare.headers.get("location"), `${a.base}/`);
});

test("revision routes inject read-only and preview flags and serve prototypes sandboxed", async (t) => {
  const h = await hub(t);
  const a = await h.session();
  const data = {
    ...artifactData(artifact()),
    pages: [
      {
        id: "overview",
        title: "Preview",
        html: '<div data-prototype="demo"></div>',
      },
    ],
    prototypes: [
      {
        id: "demo",
        title: "Demo",
        html: "<!doctype html><p>demo $&</p>",
        height: 100,
      },
    ],
  };
  await a.action("publish", { html: await assemble(data) });
  await a.feedback(a.event());
  await a.action("read");
  await a.action("publish", { html: artifact("2") });
  const live = (await a.request(`${a.base}/`)).body;
  assert.deepEqual(sessionConfig(live), {
    sessionId: a.id,
    base: a.base,
  });
  assert.equal(artifactData(live).revision, "2");
  const readonly = await a.request(`${a.base}/r/1`);
  assert.equal(readonly.code, 200);
  assert.deepEqual(sessionConfig(readonly.body), {
    sessionId: a.id,
    base: a.base,
    readonly: true,
  });
  assert.equal(artifactData(readonly.body).revision, "1");
  assert.deepEqual(
    sessionConfig((await a.request(`${a.base}/preview/1`)).body),
    {
      sessionId: a.id,
      base: a.base,
      preview: true,
    },
  );
  assert.equal((await a.request(`${a.base}/r/9`)).code, 404);
  const prototype = await a.request(`${a.base}/r/1/prototype/demo`);
  assert.equal(prototype.code, 200);
  assert.equal(prototype.body, data.prototypes[0].html);
  assert.match(prototype.headers.get("content-security-policy"), /sandbox/);
  assert.equal((await a.request(`${a.base}/r/1/prototype/nope`)).code, 404);
  const stored = await fs.readFile(
    path.join(a.directory, "artifacts/example.1.html"),
    "utf8",
  );
  assert.deepEqual(sessionConfig(stored), { sessionId: a.id, base: a.base });
  assert.deepEqual(h.record.hosts, ["127.0.0.1"]);
  const forged = await new Promise((resolve, reject) => {
    const request = http.request(
      {
        host: "127.0.0.1",
        port: h.record.port,
        path: `${a.base}/api/status`,
        headers: { host: "10.0.0.1:" + h.record.port },
      },
      (response) => resolve(response.statusCode),
    );
    request.once("error", reject);
    request.end();
  });
  assert.equal(forged, 403);
});

test("explicit feedback is retryable, remains unread until read, and blocks premature publication", async (t) => {
  const h = await hub(t);
  const a = await h.session();
  await a.action("publish", { html: artifact() });
  const event = a.event();
  const receipt = await a.feedback(event);
  assert.equal(receipt.body.status.stage, "submitted");
  assert.deepEqual(receipt.body.status.acknowledged, []);
  assert.equal((await a.feedback(event)).code, 200);
  assert.equal((await a.feedback({ ...event, text: "Changed" })).code, 409);
  assert.equal((await a.action("publish", { html: artifact("2") })).code, 409);
  const cli = async (...args) =>
    JSON.parse(
      (
        await exec(
          process.execPath,
          [helper, "read", "--session-dir", a.directory, ...args],
          { env: h.env },
        )
      ).stdout,
    );
  const output = await cli();
  assert.deepEqual(output.event.payload, event);
  assert.equal(output.status.stage, "working");
  const acked = (await a.status()).body;
  assert.equal((await cli()).event, null);
  const again = await cli("--id", event.id);
  assert.deepEqual(again.event.payload, event);
  assert.equal((await a.status()).body.acknowledgedAt, acked.acknowledgedAt);
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
  assert.equal((await a.feedback(a.event())).code, 409);
  assert.equal((await a.action("publish", { html: artifact("2") })).code, 409);
  const status = JSON.parse(
    (
      await exec(
        process.execPath,
        [helper, "status", "--session-dir", a.directory],
        { env: h.env },
      )
    ).stdout,
  );
  assert.equal(status.current.revision, "2");
});

test("a session rejects a revision reused by another artifact", async (t) => {
  const h = await hub(t);
  const a = await h.session();
  await a.action("publish", { html: artifact("1") });
  await a.feedback(a.event());
  await a.action("read");
  const duplicate = await a.action("publish", {
    html: artifact("1", "exploration", "other"),
  });
  assert.equal(duplicate.code, 409);
  assert.match(duplicate.body.error, /Revision 1 is already used/);
  assert.equal(
    await exists(path.join(a.directory, "artifacts/other.1.html")),
    false,
  );
  assert.equal((await a.status()).body.current.artifactId, "example");
  const next = await a.action("publish", {
    html: artifact("2", "exploration", "other"),
  });
  assert.equal(next.code, 200, next.body.error);
  assert.equal((await a.status()).body.current.artifactId, "other");
});

test("question actions and reply intents are unsupported", async (t) => {
  const h = await hub(t);
  const a = await h.session();
  await a.action("publish", { html: artifact() });
  const status = (await a.status()).body;
  assert.equal(Object.hasOwn(status, "question"), false);
  const browser = (await a.request(`${a.base}/`)).body;
  assert.doesNotMatch(browser, /question-dialog|question-form|send-reply/);
  assert.equal(
    (await a.feedback(a.event("clarification-reply", "1"))).code,
    400,
  );
  assert.equal(
    (await a.action("question", { text: "Typed errors?" })).code,
    400,
  );
});

test("queued rounds keep receipt order", async (t) => {
  const h = await hub(t);
  const a = await h.session();
  await a.action("publish", { html: artifact() });
  const first = a.event(),
    second = a.event();
  await a.feedback(first);
  await a.feedback(second);
  const unread = (await a.next()).body.event;
  assert.equal(unread.id, first.id);
  await a.action("read");
  const next = (await a.next()).body.event;
  assert.equal(next.id, second.id);
  assert.equal(next.sequence, unread.sequence + 1);
  assert.equal((await a.status()).body.stage, "working");
});

for (const mode of ["save", "implement"])
  test(`acceptance records explicit ${mode} mode for the exact final plan`, async (t) => {
    const h = await hub(t);
    const a = await h.session();
    await a.action("publish", { html: artifact() });
    assert.equal(
      (await a.feedback(a.event("accept-plan", "1", { mode }))).code,
      409,
    );
    await a.feedback(a.event());
    await a.action("read");
    await a.action("publish", { html: artifact("2", "plan") });
    assert.equal((await a.feedback(a.event("accept-plan", "2"))).code, 400);
    assert.equal((await a.action("complete")).code, 409);
    const acceptance = a.event("accept-plan", "2", { mode });
    assert.equal((await a.feedback(acceptance)).code, 200);
    assert.equal((await a.action("complete")).code, 409);
    await a.action("read");
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
    assert.deepEqual((await a.request("/api/sessions")).body.sessions, []);
    assert.equal(
      (await a.action("publish", { html: artifact("3", "plan") })).code,
      409,
    );
    assert.equal((await a.status()).body.accepted.mode, mode);
  });

test("implementation guidance is validated, saved with acceptance, and returned on completion", async (t) => {
  const h = await hub(t);
  const a = await h.session();
  await a.action("publish", { html: artifact("1", "plan") });
  assert.equal(
    (
      await a.feedback(
        a.event("accept-plan", "1", { mode: "save", guidance: "Do this" }),
      )
    ).code,
    400,
  );
  assert.equal(
    (
      await a.feedback(
        a.event("accept-plan", "1", {
          mode: "implement",
          guidance: "x".repeat(4001),
        }),
      )
    ).code,
    400,
  );
  const acceptance = a.event("accept-plan", "1", {
    mode: "implement",
    guidance: "  Start with the drawing question.  ",
  });
  assert.equal((await a.feedback(acceptance)).code, 200);
  assert.equal((await a.feedback(acceptance)).code, 200);
  assert.equal(
    (await a.feedback({ ...acceptance, guidance: "Different work" })).code,
    409,
  );
  const read = await a.action("read");
  assert.equal(
    read.body.event.payload.guidance,
    "Start with the drawing question.",
  );
  const complete = (await a.action("complete")).body;
  assert.equal(complete.guidance, "Start with the drawing question.");
  const record = JSON.parse(
    await fs.readFile(path.join(a.directory, "acceptance.json"), "utf8"),
  );
  assert.equal(record.guidance, complete.guidance);
});

test("the hub exits when nothing is live and start spawns a fresh one on the same port", async (t) => {
  const home = await fs.mkdtemp(path.join(os.tmpdir(), "plan-idle-"));
  const port = 30000 + Math.floor(Math.random() * 20000);
  const env = cliEnv(home, {
    INTERACTIVE_PLAN_PORT: String(port),
    INTERACTIVE_PLAN_IDLE_SECONDS: "0.3",
  });
  const config = settings(env);
  t.after(async () => {
    await killHub(config);
    await fs.rm(home, { recursive: true, force: true });
  });
  const first = JSON.parse(
    (await exec(process.execPath, [helper, "start"], { env })).stdout,
  );
  assert.equal(first.url, `http://127.0.0.1:${port}/s/${first.sessionId}/`);
  assert(first.sessionDir.startsWith(config.sessions));
  assert.deepEqual(Object.keys(first.wake), ["harness"]);
  assert(["codex", "claude-code"].includes(first.wake.harness));
  const record = JSON.parse(await fs.readFile(config.hubFile, "utf8"));
  assert.equal(record.port, port);
  assert.equal(record.version, version);
  // A session stays live until it completes or pauses, so the hub exits only
  // once this one is paused.
  await exec(
    process.execPath,
    [helper, "pause", "--session-dir", first.sessionDir, "--reason", "idle"],
    { env },
  );
  assert.equal(await waitUntil(() => !alive(record.pid), 5000), true);
  assert.equal(await exists(config.hubFile), false);
  const second = JSON.parse(
    (
      await exec(
        process.execPath,
        [helper, "start", "--session-dir", first.sessionDir],
        { env },
      )
    ).stdout,
  );
  assert.equal(second.sessionId, first.sessionId);
  assert.equal(second.url, first.url);
  const next = JSON.parse(await fs.readFile(config.hubFile, "utf8"));
  assert.notEqual(next.pid, record.pid);
  assert.equal(next.port, port);
  assert.match(
    await fs.readFile(config.hubLog, "utf8"),
    /no live sessions; exiting/,
  );
});

test("the Codex network check installs rules and reports sandbox state", async (t) => {
  const h = await hub(t);
  const a = await h.session();
  const codexHome = await fs.mkdtemp(path.join(os.tmpdir(), "plan-codex-"));
  t.after(() => fs.rm(codexHome, { recursive: true, force: true }));
  const check = path.join(path.dirname(helper), "check.mjs");
  await exec(process.execPath, [check, "--codex-rules"], {
    env: { ...h.env, CODEX_HOME: codexHome },
  });
  const rules = await fs.readFile(
    path.join(codexHome, "rules", "interactive-plan.rules"),
    "utf8",
  );
  assert.equal(rules.match(/^prefix_rule\(pattern=\["node", /gm).length, 3);
  assert.ok(rules.includes(helper));
  const report = JSON.parse(
    (
      await exec(process.execPath, [check, a.directory], {
        env: { ...h.env, CODEX_HOME: codexHome, CODEX_SANDBOX: "seatbelt" },
      })
    ).stdout,
  );
  assert.equal(report.codex.present, true);
});

test("a moved session still serves its current and earlier revisions", async (t) => {
  const h = await hub(t);
  const a = await h.session();
  await a.action("publish", { html: artifact("1") });
  await a.action("publish", { html: artifact("2") });
  const moved = a.directory + "-moved";
  await fs.rename(a.directory, moved);
  const registered = await fetch(h.server.origin + "/agent/register", {
    method: "POST",
    headers: {
      authorization: `Bearer ${h.record.secret}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      sessionDir: moved,
      wake: { harness: "codex", thread: "thread-moved" },
    }),
  });
  assert.equal(registered.status, 200);
  assert.equal((await a.request(`${a.base}/`)).code, 200);
  assert.equal((await a.request(`${a.base}/r/1`)).code, 200);
  const manifest = await a.request(`${a.base}/api/page-set?revision=1`);
  assert.equal(manifest.code, 200);
  const slot = manifest.body.pages.find((item) => item.id === "overview");
  assert.equal(
    (
      await a.request(
        `${a.base}/api/page?revision=1&id=overview&version=${slot.version}`,
      )
    ).code,
    200,
  );
});

test("start replaces a stale hub record, and helper commands reattach after a crash without losing the queue", async (t) => {
  const home = await fs.mkdtemp(path.join(os.tmpdir(), "plan-stale-"));
  const env = cliEnv(home, { INTERACTIVE_PLAN_PORT: "0" });
  const config = settings(env);
  t.after(async () => {
    await killHub(config);
    await fs.rm(home, { recursive: true, force: true });
  });
  const dead = spawn(process.execPath, ["-e", ""]);
  await new Promise((resolve) => dead.once("exit", resolve));
  await fs.mkdir(config.hubDir, { recursive: true });
  await fs.writeFile(
    config.hubFile,
    JSON.stringify({
      pid: dead.pid,
      port: 1,
      hosts: ["127.0.0.1"],
      version,
      startedAt: "2000-01-01T00:00:00Z",
      secret: "stale",
    }),
  );
  const started = JSON.parse(
    (await exec(process.execPath, [helper, "start"], { env })).stdout,
  );
  const record = JSON.parse(await fs.readFile(config.hubFile, "utf8"));
  assert.notEqual(record.pid, dead.pid);
  assert.notEqual(record.port, 1);
  const source = path.join(home, "source.json");
  const shared = {
    artifactId: "example",
    revision: "1",
    kind: "exploration",
    title: "Example work",
  };
  const command = (...args) =>
    exec(
      process.execPath,
      [helper, ...args, "--session-dir", started.sessionDir],
      {
        env,
      },
    );
  const agreedFile = path.join(home, "agreed.html");
  await fs.writeFile(
    agreedFile,
    await buildPage(source, {
      ...shared,
      page: {
        id: "agreed",
        title: "Agreed so far",
        agreements: [],
        task: { title: "The task", html: "<p>What the plan builds.</p>" },
      },
    }),
  );
  const pagesFile = path.join(home, "pages.json");
  await fs.writeFile(
    pagesFile,
    JSON.stringify({ pages: [{ id: "overview", title: "Overview" }] }),
  );
  await command("publish", "--file", agreedFile, "--pages", pagesFile);
  const overviewFile = path.join(home, "overview.html");
  await fs.writeFile(
    overviewFile,
    await buildPage(source, {
      ...shared,
      page: { id: "overview", title: "Overview", html: "<p>Ready</p>" },
    }),
  );
  await command("publish", "--file", overviewFile);
  const origin = `http://127.0.0.1:${record.port}`;
  const event = {
    sessionId: started.sessionId,
    artifactId: "example",
    revision: "1",
    intent: "feedback-only",
    id: crypto.randomUUID(),
    groups: {},
    text: "Survive a restart",
  };
  const receipt = await fetch(`${origin}/s/${started.sessionId}/api/feedback`, {
    method: "POST",
    headers: { Origin: origin, "Content-Type": "application/json" },
    body: JSON.stringify(event),
  });
  assert.equal(receipt.status, 200);
  process.kill(record.pid, "SIGKILL");
  assert.equal(await waitUntil(() => !alive(record.pid)), true);
  const output = JSON.parse(
    (
      await exec(
        process.execPath,
        [helper, "read", "--session-dir", started.sessionDir],
        { env },
      )
    ).stdout,
  );
  assert.deepEqual(output.event.payload, event);
  const next = JSON.parse(await fs.readFile(config.hubFile, "utf8"));
  assert.notEqual(next.pid, record.pid);
  const connection = JSON.parse(
    await fs.readFile(path.join(started.sessionDir, "connection.json"), "utf8"),
  );
  assert.equal(connection.sessionId, started.sessionId);
  assert.equal(connection.origin, `http://127.0.0.1:${next.port}`);
});

// A reviewer's screenshot arrives as bytes with no name and no type worth
// trusting, so the hub decides both and writes the file itself.
test("an image upload is decided by its bytes, capped, and named by the hub", async (t) => {
  const h = await hub(t);
  const a = await h.session();
  const send = (body, headers = {}) =>
    fetch(`${h.server.origin}${a.base}/api/upload`, {
      method: "POST",
      headers: { Origin: h.server.origin, ...headers },
      body,
    });
  const pad = (magic, size = 64) =>
    Buffer.concat([Buffer.from(magic), Buffer.alloc(size)]);
  const png = pad([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  const jpeg = pad([0xff, 0xd8, 0xff]);
  const gif = pad([0x47, 0x49, 0x46, 0x38]);
  const webp = Buffer.concat([
    Buffer.from("RIFF"),
    Buffer.alloc(4),
    Buffer.from("WEBP"),
    Buffer.alloc(64),
  ]);

  const accepted = await send(png);
  const record = await accepted.json();
  assert.equal(accepted.status, 201, record.error);
  assert.equal(record.type, "image/png");
  assert.equal(record.bytes, png.length);
  assert.match(record.id, /^[0-9a-f]{16}$/);
  // The hub names the file, so the caller never picks a path.
  assert.equal(
    record.path,
    path.join(a.directory, "uploads", `${record.id}.png`),
  );
  assert.deepEqual(await fs.readFile(record.path), png);

  for (const [bytes, type] of [
    [jpeg, "image/jpeg"],
    [gif, "image/gif"],
    [webp, "image/webp"],
  ])
    assert.equal((await send(bytes).then((r) => r.json())).type, type);

  // A HEIC from a phone, and a PNG signature that a name cannot fake.
  const heic = Buffer.concat([
    Buffer.alloc(4),
    Buffer.from("ftypheic"),
    Buffer.alloc(64),
  ]);
  const refused = await send(heic);
  assert.equal(refused.status, 415);
  assert.match((await refused.json()).error, /PNG, JPEG, WebP and GIF/);

  const tooBig = await send(
    Buffer.concat([png, Buffer.alloc(10 * 1024 * 1024)]),
  );
  assert.equal(tooBig.status, 413);
  assert.match((await tooBig.json()).error, /10MB/);

  assert.equal((await send(png, { Origin: "http://example.com" })).status, 403);

  // One request is bounded and the session is not, so a long review never
  // meets a ceiling.
  for (let n = 0; n < 30; n++) assert.equal((await send(png)).status, 201);
  assert.equal(
    (await fs.readdir(path.join(a.directory, "uploads"))).length,
    34,
  );
});

test("a note carries its images by path, and removing one deletes the file", async (t) => {
  const h = await hub(t);
  const a = await h.session();
  assert.equal((await a.action("publish", { html: artifact() })).code, 200);
  const png = Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    Buffer.alloc(64),
  ]);
  const stored = await fetch(`${h.server.origin}${a.base}/api/upload`, {
    method: "POST",
    headers: { Origin: h.server.origin },
    body: png,
  }).then((r) => r.json());

  const note = (attachments) => ({
    id: crypto.randomUUID(),
    topic: "overview",
    anchor: "The strip under the header",
    text: "This is what I mean.",
    attachments,
  });
  // A note may only name an image this session holds.
  const rejected = await a.feedback(
    a.event("feedback-only", "1", {
      groups: {
        notes: [
          note([
            {
              id: "0".repeat(16),
              path: "/tmp/x.png",
              type: "image/png",
              bytes: 1,
            },
          ]),
        ],
      },
    }),
  );
  assert.equal(rejected.code, 400);
  assert.match(rejected.body.error, /not in this session/);

  const event = a.event("feedback-only", "1", {
    groups: { notes: [note([stored])] },
  });
  assert.equal((await a.feedback(event)).code, 200);
  // The agent reads the path off the note, and the bytes are on disk under it.
  const delivered = (await a.action("read", { id: event.id })).body.event;
  assert.deepEqual(delivered.payload.groups.notes[0].attachments, [stored]);
  assert(await exists(stored.path));

  const removed = await fetch(
    `${h.server.origin}${a.base}/api/upload/${stored.id}`,
    { method: "DELETE", headers: { Origin: h.server.origin } },
  );
  assert.equal(removed.status, 200);
  assert.deepEqual(await removed.json(), { id: stored.id, removed: true });
  assert.equal(await exists(stored.path), false);
  // Removing the same image twice is not an error, so a retry is safe.
  assert.deepEqual(
    await fetch(`${h.server.origin}${a.base}/api/upload/${stored.id}`, {
      method: "DELETE",
      headers: { Origin: h.server.origin },
    }).then((r) => r.json()),
    { id: stored.id, removed: false },
  );
});

test("a drawing answer saves a scene and PNG preview in its own session", async (t) => {
  const h = await hub(t);
  const a = await h.session();
  const other = await h.session();
  assert.equal((await a.action("publish", { html: artifact() })).code, 200);
  const scene = {
    type: "excalidraw",
    version: 2,
    elements: [{ id: "shape" }],
    appState: {},
    files: {},
  };
  const post = (suffix, body) =>
    fetch(`${h.server.origin}${a.base}/api/${suffix}`, {
      method: "POST",
      headers: { Origin: h.server.origin },
      body,
    });
  const saved = await post("drawing-scene", JSON.stringify(scene));
  assert.equal(saved.status, 201);
  const drawing = await saved.json();
  assert.equal(
    drawing.path,
    path.join(a.directory, "scenes", `${drawing.id}.excalidraw`),
  );
  assert.deepEqual(JSON.parse(await fs.readFile(drawing.path, "utf8")), scene);
  assert.deepEqual(
    await fetch(
      `${h.server.origin}${a.base}/api/drawing-scene/${drawing.id}`,
    ).then((r) => r.json()),
    scene,
  );
  const png = Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    Buffer.alloc(64),
  ]);
  const preview = await (await post("upload", png)).json();
  const answer = {
    kind: "drawing",
    topic: "overview",
    label: "System boundary",
    revision: "1",
    sceneId: drawing.id,
    previewId: preview.id,
  };
  const event = a.event("feedback-only", "1", {
    groups: { answers: { "overview/boundary": answer } },
  });
  assert.equal((await a.feedback(event)).code, 200);
  const read = (await a.action("read", { id: event.id })).body.event.payload
    .groups.answers["overview/boundary"];
  assert.equal(read.scenePath, drawing.path);
  assert.equal(read.previewPath, preview.path);
  assert(await exists(read.scenePath));
  assert(await exists(read.previewPath));
  const foreign = await (
    await fetch(`${h.server.origin}${other.base}/api/drawing-scene`, {
      method: "POST",
      headers: { Origin: h.server.origin },
      body: JSON.stringify(scene),
    })
  ).json();
  assert.equal(
    (
      await a.feedback(
        a.event("feedback-only", "1", {
          groups: {
            answers: {
              "overview/foreign": { ...answer, sceneId: foreign.id },
            },
          },
        }),
      )
    ).code,
    404,
  );
  assert.equal((await post("drawing-scene", "not JSON")).status, 400);
  assert.equal(
    (await post("drawing-scene", JSON.stringify({ ...scene, elements: [] })))
      .status,
    400,
  );
  assert.equal(
    (await post("drawing-scene", Buffer.alloc(10 * 1024 * 1024 + 1))).status,
    413,
  );
  assert.equal(
    (
      await fetch(`${h.server.origin}${a.base}/api/drawing-scene`, {
        method: "POST",
        headers: { Origin: "http://example.com" },
        body: JSON.stringify(scene),
      })
    ).status,
    403,
  );
});

test("the component fixture builds, so every component's markup stays valid", async (t) => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), "plan-fixture-"));
  t.after(() => fs.rm(directory, { recursive: true, force: true }));
  const output = path.join(directory, "fixture.html");
  await exec(process.execPath, [
    path.join(
      root,
      "ai-harness/skills/interactive-plan/scripts/fixture/build.mjs",
    ),
    output,
  ]);
  // The fixture is the one place every component is rendered with real
  // content, so a structural mistake in it is a mistake in a component:
  // build.mjs refuses duplicate control IDs, a missing data-label, a
  // decision with one option, and an option label over 24 characters.
  const pages = artifactData(await fs.readFile(output, "utf8")).pages;
  const html = pages.map((page) => page.html).join("");
  for (const attribute of [
    'data-choice="retry"',
    'data-multiselect="scope"',
    'data-question="threshold"',
    'data-drawing-question="boundary"',
    'data-lines="3-4"',
    "data-notes=",
    "data-terms=",
  ])
    assert.ok(html.includes(attribute), `fixture lost ${attribute}`);
});
