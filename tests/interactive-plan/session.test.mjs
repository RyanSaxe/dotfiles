import assert from "node:assert/strict";
import { execFile, spawn } from "node:child_process";
import crypto from "node:crypto";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { promisify } from "node:util";
import { fileURLToPath } from "node:url";
import test from "node:test";
import vm from "node:vm";
import { compareFiles } from "../../ai-harness/skills/interactive-plan/components/before-after/diff.mjs";
import {
  createReviewAlerts,
  reviewAlert,
} from "../../ai-harness/skills/interactive-plan/assets/notifications.mjs";

test("choice tabs preview, select, clear, and support keyboard navigation", async () => {
  const listeners = {};
  const tabs = Array.from({ length: 7 }, (_, index) => {
    const attributes = new Map([["aria-pressed", "false"]]);
    return {
      dataset: { value: `option-${index}` },
      focused: false,
      getAttribute: (name) => attributes.get(name) ?? null,
      setAttribute: (name, value) => attributes.set(name, value),
      closest: () => tabs[index],
      focus() {
        this.focused = true;
      },
      click() {
        listeners.click({ target: this });
        const clearing = this.getAttribute("aria-pressed") === "true";
        for (const tab of tabs) tab.setAttribute("aria-pressed", "false");
        if (!clearing) this.setAttribute("aria-pressed", "true");
      },
    };
  });
  const panels = tabs.map((tab) => ({
    dataset: { choicePanel: tab.dataset.value },
    hidden: false,
  }));
  const root = {
    dataset: {},
    querySelectorAll(selector) {
      return selector.includes("tabpanel") ? panels : tabs;
    },
    addEventListener(type, listener) {
      listeners[type] = listener;
    },
  };
  let render;
  const source = await fs.readFile(
    path.join(
      path.dirname(fileURLToPath(import.meta.url)),
      "../../ai-harness/skills/interactive-plan/components/choice-tabs/behavior.js",
    ),
    "utf8",
  );
  vm.runInNewContext(source, {
    window: { addEventListener: (_type, listener) => (render = listener) },
    MutationObserver: class {
      observe() {}
    },
    queueMicrotask,
  });
  render({
    detail: {
      element: { querySelectorAll: () => [root] },
    },
  });

  assert.equal(root.dataset.preview, "true");
  assert.equal(tabs[0].getAttribute("aria-selected"), "true");
  assert.equal(panels.filter((panel) => !panel.hidden).length, 1);
  tabs[4].click();
  await Promise.resolve();
  assert.equal(root.dataset.preview, "false");
  assert.equal(tabs[4].getAttribute("aria-selected"), "true");
  assert.equal(panels[4].hidden, false);
  tabs[4].click();
  await Promise.resolve();
  assert.equal(root.dataset.preview, "true");
  assert.equal(tabs[0].getAttribute("aria-selected"), "true");

  const press = (tab, key) => {
    let prevented = false;
    listeners.keydown({
      target: tab,
      key,
      preventDefault: () => (prevented = true),
    });
    assert.equal(prevented, true);
  };
  press(tabs[0], "End");
  await Promise.resolve();
  assert.equal(tabs[6].focused, true);
  assert.equal(tabs[6].getAttribute("aria-selected"), "true");
  press(tabs[6], "ArrowRight");
  await Promise.resolve();
  assert.equal(tabs[0].getAttribute("aria-selected"), "true");
  press(tabs[0], "ArrowLeft");
  await Promise.resolve();
  assert.equal(tabs[6].getAttribute("aria-selected"), "true");
  press(tabs[6], "Home");
  await Promise.resolve();
  assert.equal(tabs[0].getAttribute("aria-selected"), "true");
});

test("choice tab styles leave panel contents under page control", async () => {
  const directory = path.join(
    path.dirname(fileURLToPath(import.meta.url)),
    "../../ai-harness/skills/interactive-plan/components/choice-tabs",
  );
  const [markup, styles] = await Promise.all([
    fs.readFile(path.join(directory, "markup.html"), "utf8"),
    fs.readFile(path.join(directory, "styles.css"), "utf8"),
  ]);
  assert.equal((markup.match(/role="tab"/g) || []).length, 3);
  assert.equal((markup.match(/role="tabpanel"/g) || []).length, 3);
  assert.doesNotMatch(styles, /\.choice-tabs-panel\s+[.#[:]/);
  assert.match(styles, /overflow-x:\s*auto/);
  assert.doesNotMatch(styles, /\.choice-tabs-panel[^}]*height\s*:/s);
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
  await promisify(execFile)("git", ["apply", `-p${strip}`, patchPath], {
    cwd: directory,
  });
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

function alertFixture({
  storage = new Map(),
  permission = "default",
  supported = true,
  blockedStorage = false,
  locks,
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
    hidden: true,
    title: "",
    hasFocus: () => false,
  });
  const host = Object.assign(new EventTarget(), {
    document,
    Notification: supported ? Notification : undefined,
    isSecureContext: true,
    location: { protocol: "http:", hash: "#overview" },
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
  const plan = { artifactId: "example", revision: "1", title: "Example plan" };
  const alerts = createReviewAlerts({
    window: host,
    button,
    sessionId: "test-session",
    plan,
    open: (url) => opened.push(url),
  });
  const status = {
    stage: "updated",
    current: {
      artifactId: "example",
      revision: "2",
      url: "/artifacts/example.2.html",
    },
  };
  return {
    alerts,
    host,
    button,
    sent,
    opened,
    status,
    plan,
    requests: () => requests,
  };
}

test("enabling alerts skips the current review and deduplicates later events across tabs", async () => {
  const storage = new Map();
  let queue = Promise.resolve();
  const locks = { request: (_key, callback) => (queue = queue.then(callback)) };
  const a = alertFixture({ storage, locks });
  await a.alerts.update(a.status);
  assert.equal(a.sent.length, 0);
  assert.equal(a.requests(), 0);
  await a.button.onclick();
  assert.equal(a.requests(), 1);
  assert.equal(a.sent.length, 0);
  await a.alerts.update(a.status);
  const b = alertFixture({ storage, locks, permission: "granted" });
  await b.alerts.update(b.status);
  assert.equal(b.sent.length, 0);
  const next = {
    ...a.status,
    current: {
      ...a.status.current,
      revision: "3",
      url: "/artifacts/example.3.html",
    },
  };
  await Promise.all([a.alerts.update(next), b.alerts.update(next)]);
  assert.equal(a.sent.length + b.sent.length, 1);
  await a.alerts.update({ ...next, stage: "working" });
  a.sent[0].onclick();
  assert.deepEqual(a.opened, [next.current.url]);
  const reload = alertFixture({ storage, locks, permission: "granted" });
  await reload.alerts.update(next);
  assert.equal(reload.sent.length, 0);
});

test("granted permission enables automatically unless explicitly disabled; re-enabling skips backlog", async () => {
  const storage = new Map();
  const a = alertFixture({ storage, permission: "granted" });
  await a.alerts.update(a.status);
  assert.equal(a.button.textContent, "Disable notifications");
  assert.equal(a.requests(), 0);
  assert.equal(a.sent.length, 0);
  const next = { ...a.status, current: { ...a.status.current, revision: "3" } };
  await a.alerts.update(next);
  assert.equal(a.sent.length, 1);
  await a.button.onclick();
  const b = alertFixture({ storage, permission: "granted" });
  await b.alerts.update({
    ...next,
    current: { ...next.current, revision: "4" },
  });
  assert.equal(b.button.textContent, "Enable notifications");
  assert.equal(b.sent.length, 0);
  await b.button.onclick();
  await b.alerts.update();
  assert.equal(b.sent.length, 0);
  await b.alerts.update({
    ...next,
    current: {
      ...next.current,
      revision: "5",
      publishedAt: "2000-01-01T00:00:00Z",
    },
  });
  assert.equal(b.sent.length, 0);
  await b.alerts.update({
    ...next,
    current: {
      ...next.current,
      revision: "6",
      publishedAt: "2099-01-01T00:00:00Z",
    },
  });
  assert.equal(b.sent.length, 1);
});

test("alerts are limited to review-ready stages", async () => {
  const a = alertFixture();
  await a.button.onclick();
  a.host.document.hidden = false;
  a.host.document.hasFocus = () => true;
  a.host.location.hash = "#feedback";
  await a.alerts.update(a.status);
  await a.alerts.update(a.status);
  assert.equal(a.sent.length, 1);
  assert.equal(a.sent[0].options.body, a.plan.title);
  assert.equal(a.sent[0].closed, undefined);
  await a.alerts.update({ ...a.status, stage: "working" });
  assert.equal(a.sent[0].closed, undefined);
  a.sent[0].onclick();
  assert.deepEqual(a.opened, [a.status.current.url]);
  for (const stage of ["submitted", "working", "complete"])
    assert.equal(reviewAlert({ ...a.status, stage }), null);
});

test("denied, unavailable, and failed notifications retain the title fallback", async () => {
  for (const options of [{ permission: "denied" }, { supported: false }]) {
    const a = alertFixture(options);
    await a.alerts.update(a.status);
    assert.equal(a.button.disabled, true);
    assert.equal(a.sent.length, 0);
    assert.match(a.host.document.title, /new review/);
  }
  const a = alertFixture({ blockedStorage: true });
  await a.button.onclick();
  await a.alerts.update(a.status);
  await a.alerts.update(a.status);
  assert.equal(a.sent.length, 1);
  a.sent[0].onerror();
  assert.equal(a.button.disabled, true);
  assert.match(a.button.title, /delivery failed/);
  assert.match(a.host.document.title, /new review/);
});
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

test("preserved prototypes retain exact executable source without escaping into the frame", async (t) => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), "plan-prototype-"));
  t.after(() => fs.rm(directory, { recursive: true, force: true }));
  const html =
    '<!doctype html><button id="try">Try</button><script>document.querySelector("button").onclick = () => alert("$&");</script>';
  await fs.writeFile(path.join(directory, "prototype.html"), html);
  const data = {
    ...artifactData(artifact()),
    pages: [
      {
        id: "overview",
        title: "Preview",
        html: '<div data-prototype="demo"></div><code>data-prototype="ID"</code>',
      },
    ],
    prototypes: [
      {
        id: "demo",
        title: "Approved interaction",
        file: "prototype.html",
        height: 420,
      },
    ],
  };
  const source = path.join(directory, "source.json");
  await fs.writeFile(source, JSON.stringify(data));
  const result = await build(source);
  const parsed = artifactData(result);
  assert.equal(parsed.prototypes[0].html, html);
  assert.equal(parsed.prototypes[0].file, undefined);
  assert(!result.includes(html));
  for (const prototypes of [
    [],
    [null],
    [{ ...parsed.prototypes[0], height: 0 }],
    [{ ...parsed.prototypes[0], html: "" }],
    [parsed.prototypes[0], parsed.prototypes[0]],
  ])
    await assert.rejects(assemble({ ...parsed, prototypes }));
  await fs.writeFile(
    source,
    JSON.stringify({ ...data, prototypes: [{ ...data.prototypes[0], html }] }),
  );
  await assert.rejects(build(source), /file.*html|html.*file/);
});

test("publication resolves exact mixed sources from saved feedback before hashing", async (t) => {
  const a = await fixture(t);
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
  assert.equal((await a.request("/api/feedback", feedback)).code, 200);
  await a.action("ack", { id: feedback.id });
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
  ])
    await assert.rejects(
      assemble({ ...data, agreements: [{ ...entry, sourceRefs }] }),
    );
});

test("choice sources preserve readable labels and complete checklist snapshots", async (t) => {
  const a = await fixture(t);
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
  assert.equal((await a.request("/api/feedback", feedback)).code, 200);
  await a.action("ack", { id: feedback.id });
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
  const legacy = {
    ...data,
    pages: [
      ...data.pages,
      { id: "agreed", title: "Agreed", html: "Previous decision" },
    ],
  };
  assert.equal(artifactData(await assemble(legacy)).pages.length, 2);
  await assert.rejects(assemble({ ...legacy, agreements: [] }));
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
      ...data,
      agreements: [{ ...metadata, file: "decision.html" }],
    }),
  );
  assert.equal(artifactData(await build(source)).agreements[0].html, html);
});

test("agreements survive topic changes and targeted feedback without rewriting snapshots", async (t) => {
  const a = await fixture(t);
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
    assert.equal((await a.request("/api/feedback", event)).code, 200);
    const received = await a.request("/agent/next");
    assert.equal(
      received.body.event.payload.groups.notes[0].agreementId,
      entry.id,
    );
    assert.equal(received.body.event.payload.intent, "feedback-only");
    await a.action("ack", { id: event.id });
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

test("question actions and reply intents are unsupported", async (t) => {
  const a = await fixture(t);
  await a.action("publish", { html: artifact() });
  const status = (await a.request("/api/status")).body;
  assert.equal(Object.hasOwn(status, "question"), false);
  const browser = await (await fetch(a.server.origin)).text();
  assert.doesNotMatch(browser, /question-dialog|question-form|send-reply/);
  assert.equal(
    (await a.request("/api/feedback", a.event("clarification-reply", "1")))
      .code,
    400,
  );
  assert.equal(
    (await a.action("question", { text: "Typed errors?" })).code,
    400,
  );
});

test("queued rounds keep receipt order", async (t) => {
  const a = await fixture(t);
  await a.action("publish", { html: artifact() });
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
  assert.equal((await a.request("/api/status")).body.stage, "working");
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
