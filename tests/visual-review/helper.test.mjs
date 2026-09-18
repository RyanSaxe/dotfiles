import assert from "node:assert/strict";
import test from "node:test";
import {
  mergePages,
  parsePages,
  questionStatus,
  serve,
} from "../../ai-harness/skills/visual-review/scripts/session.mjs";
import {
  createSampleRepository,
  removeAll,
  temporaryDirectory,
} from "./fixtures/repo.mjs";

/** A helper plus the two sides of the protocol: the browser and the agent. */
async function open(t) {
  const repo = await createSampleRepository();
  const sessionDir = await temporaryDirectory("session");
  const session = await serve(sessionDir, { repo: repo.root });
  const connection = await fetch(session.origin + "/api/state").then((r) =>
    r.json(),
  );
  const { token } = await import("node:fs/promises")
    .then((fs) => fs.readFile(sessionDir + "/connection.json", "utf8"))
    .then(JSON.parse);

  const post = async (route, body, headers) => {
    const response = await fetch(session.origin + route, {
      method: "POST",
      headers: { "Content-Type": "application/json", ...headers },
      body: JSON.stringify({ sessionId: connection.sessionId, ...body }),
    });
    return { status: response.status, body: await response.json() };
  };
  const browser = (route, body) =>
    post(route, body, { Origin: session.origin });
  const agent = (body) =>
    post("/agent/action", body, { authorization: `Bearer ${token}` });
  const next = async () => {
    const response = await fetch(session.origin + "/agent/next", {
      headers: { authorization: `Bearer ${token}` },
    });
    return response.json();
  };
  const state = () =>
    fetch(session.origin + "/api/state").then((r) => r.json());

  t.after(async () => {
    await session.close();
    await removeAll(sessionDir, repo.root, repo.origin);
  });
  return { session, browser, agent, next, state, repo };
}

const question = (state, id) =>
  state.questions.find((entry) => entry.id === id);

test("parses and merges an outline the way replanning expects", () => {
  assert.deepEqual(parsePages("a=First,b=Second thing"), [
    { id: "a", title: "First", status: "planned" },
    { id: "b", title: "Second thing", status: "planned" },
  ]);
  assert.throws(() => parsePages("A=Upper"), /Invalid page id/);
  assert.throws(() => parsePages("a=One,a=Two"), /Duplicate page id/);
  assert.throws(() => parsePages("noequals"), /id=Title/);
  assert.throws(() => parsePages(""), /at least one page/);

  const existing = [
    { id: "a", title: "First", status: "written", revision: 2 },
    { id: "b", title: "Second", status: "planned" },
  ];
  const replanned = mergePages(existing, parsePages("a=Renamed,c=Third"));
  assert.deepEqual(
    replanned.map((page) => `${page.id}:${page.status}:${page.title}`),
    ["a:written:Renamed", "c:planned:Third"],
    "an unread page can be replaced, a written one keeps its content",
  );
  assert.equal(replanned[0].revision, 2);

  const dropped = mergePages(existing, parsePages("c=Third"));
  assert.deepEqual(
    dropped.map((page) => page.id),
    ["c", "a"],
    "a written page left out of the new plan is kept, not silently lost",
  );

  const appended = mergePages(existing, parsePages("c=Third"), true);
  assert.deepEqual(
    appended.map((page) => page.id),
    ["a", "b", "c"],
  );
  assert.throws(
    () => mergePages(existing, parsePages("b=Again"), true),
    /already planned/,
  );
});

test("reads a question's status from its pages", () => {
  const pages = [{ id: "a", status: "planned" }];
  assert.equal(questionStatus({ pages: [] }), "asked");
  assert.equal(questionStatus({ pages }), "planned");
  assert.equal(
    questionStatus({ pages: [{ id: "a", status: "written" }, ...pages] }),
    "writing",
  );
  assert.equal(questionStatus({ pages, completedAt: "now" }), "done");
});

test("carries one question from ask to done", async (t) => {
  const helper = await open(t);

  const asked = await helper.browser("/api/ask", {
    id: "ask1",
    text: "How does the retry loop work?",
  });
  assert.equal(asked.status, 200);
  let state = await helper.state();
  assert.equal(question(state, "ask1").status, "asked");
  assert.equal(state.pending, 1);
  assert.equal(
    question(state, "ask1").text,
    "How does the retry loop work?",
    "the literal question is kept for the first page to show",
  );

  const waiting = await helper.next();
  assert.equal(waiting.event.id, "ask1");
  assert.equal(waiting.event.kind, "ask");

  await helper.agent({ action: "ack", id: "ask1" });
  assert.equal((await helper.state()).pending, 0);
  assert.equal(
    (await helper.next()).event,
    null,
    "an acknowledged event is not returned again",
  );

  await helper.agent({
    action: "plan",
    question: "ask1",
    title: "Retry loop",
    pages: "overview=Overview map,loop=The loop,breaker=The breaker",
  });
  state = await helper.state();
  assert.equal(question(state, "ask1").title, "Retry loop");
  assert.equal(question(state, "ask1").status, "planned");
  assert.deepEqual(
    question(state, "ask1").pages.map((page) => page.status),
    ["planned", "planned", "planned"],
  );

  await helper.agent({
    action: "status",
    question: "ask1",
    text: "reading 3 files",
  });
  assert.equal(
    (await helper.state()).questions[0].statusLine,
    "reading 3 files",
  );

  await helper.agent({
    action: "page",
    question: "ask1",
    id: "overview",
    markdown: "# Overview\n\nThe loop lives in `src/client.py`.\n",
  });
  state = await helper.state();
  assert.equal(question(state, "ask1").status, "writing");
  const overview = question(state, "ask1").pages[0];
  assert.equal(overview.status, "written");
  assert.equal(overview.revision, 1);

  const fetched = await fetch(
    helper.session.origin + "/api/page?question=ask1&id=overview",
  );
  assert.equal(
    fetched.headers.get("content-type"),
    "text/markdown; charset=utf-8",
  );
  assert.match(await fetched.text(), /The loop lives in/);

  await helper.agent({
    action: "page",
    question: "ask1",
    id: "overview",
    markdown: "# Overview\n\nRewritten.\n",
  });
  state = await helper.state();
  assert.equal(
    question(state, "ask1").pages[0].revision,
    2,
    "republishing marks the page updated without changing its place",
  );

  await helper.agent({ action: "done", question: "ask1" });
  state = await helper.state();
  assert.equal(question(state, "ask1").status, "done");
  assert.deepEqual(
    question(state, "ask1").pages.map((page) => page.id),
    ["overview"],
    "pages that were planned but never written leave the outline",
  );
  assert.equal(state.stage, "ready");
});

test("refuses a page that was never planned", async (t) => {
  const helper = await open(t);
  await helper.browser("/api/ask", { id: "ask1", text: "Anything" });
  await helper.agent({
    action: "plan",
    question: "ask1",
    title: "Answer",
    pages: "overview=Overview",
  });
  const rejected = await helper.agent({
    action: "page",
    question: "ask1",
    id: "surprise",
    markdown: "# No\n",
  });
  assert.equal(rejected.status, 400);
  assert.match(rejected.body.error, /not in the plan/);
});

test("routes a follow-up to the question it came from", async (t) => {
  const helper = await open(t);
  await helper.browser("/api/ask", { id: "ask1", text: "First question" });
  await helper.agent({
    action: "plan",
    question: "ask1",
    title: "First",
    pages: "overview=Overview",
  });
  await helper.agent({ action: "ack", id: "ask1" });

  await helper.browser("/api/ask", {
    id: "ask2",
    text: "Why is that?",
    context: { questionId: "ask1", pageId: "overview", quote: "the loop" },
  });
  let state = await helper.state();
  assert.equal(
    state.questions.length,
    1,
    "a follow-up extends its question instead of opening a new one",
  );
  assert.deepEqual(question(state, "ask1").followUps[0].context, {
    questionId: "ask1",
    pageId: "overview",
    quote: "the loop",
  });
  const event = (await helper.next()).event;
  assert.equal(event.id, "ask2");
  assert.equal(event.payload.context.pageId, "overview");

  await helper.browser("/api/ask", {
    id: "ask3",
    text: "What do these lines do?",
    context: { file: "src/client.py", ref: "main", lines: [1, 2] },
  });
  state = await helper.state();
  assert.equal(
    state.questions.length,
    2,
    "a selection with no question of its own opens one",
  );
  assert.deepEqual(question(state, "ask3").context, {
    file: "src/client.py",
    ref: "main",
    lines: [1, 2],
  });

  const picked = await helper.browser("/api/choose", {
    id: "pick1",
    questionId: "ask1",
    pageId: "overview",
    blockId: "block-2",
    option: "The write path",
  });
  assert.equal(picked.status, 200);
  const events = [];
  for (let i = 0; i < 3; i += 1) {
    const pending = (await helper.next()).event;
    if (!pending) break;
    events.push(pending);
    await helper.agent({ action: "ack", id: pending.id });
  }
  const choice = events.find((entry) => entry.id === "pick1");
  assert.equal(
    choice.kind,
    "ask",
    "a picked option reaches the agent as an ask",
  );
  assert.equal(choice.payload.text, "The write path");
  assert.equal(choice.payload.context.blockId, "block-2");
});

test("a follow-up reopens the question it belongs to", async (t) => {
  const helper = await open(t);
  await helper.browser("/api/ask", { id: "ask1", text: "How does it work?" });
  await helper.agent({
    action: "plan",
    question: "ask1",
    title: "How it works",
    pages: "overview=Overview",
  });
  await helper.agent({
    action: "page",
    question: "ask1",
    id: "overview",
    markdown: "# Overview\n",
  });
  await helper.agent({ action: "done", question: "ask1" });
  assert.equal(question(await helper.state(), "ask1").status, "done");

  // Finishing the pages does not end the conversation about them.
  const later = await helper.browser("/api/ask", {
    id: "ask2",
    text: "Why that way?",
    context: { questionId: "ask1", pageId: "overview" },
  });
  assert.equal(later.status, 200);
  const state = await helper.state();
  assert.equal(state.questions.length, 1);
  assert.equal(question(state, "ask1").status, "writing");
  assert.equal(question(state, "ask1").followUps.length, 1);

  const extended = await helper.agent({
    action: "plan",
    question: "ask1",
    title: "How it works",
    pages: "why=Why that way",
    append: true,
  });
  assert.equal(extended.status, 200);
});

test("refuses events from the wrong source, session, or shape", async (t) => {
  const helper = await open(t);

  const noOrigin = await fetch(helper.session.origin + "/api/ask", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ sessionId: "x", id: "a", text: "b" }),
  });
  assert.equal(noOrigin.status, 403, "a browser post needs a matching Origin");

  const noToken = await fetch(helper.session.origin + "/agent/next");
  assert.equal(noToken.status, 403, "agent routes need the bearer token");

  const wrongSession = await helper.browser("/api/ask", {
    sessionId: "another-session",
    id: "ask1",
    text: "Anything",
  });
  assert.equal(wrongSession.status, 409);

  for (const body of [
    { id: "", text: "Anything" },
    { id: "ask1", text: "   " },
    { id: "ask1", text: "Anything", context: { questionId: "missing" } },
  ]) {
    const result = await helper.browser("/api/ask", body);
    assert.ok(
      result.status >= 400,
      `${JSON.stringify(body)} should be refused`,
    );
  }

  const repeated = await helper.browser("/api/ask", {
    id: "ask9",
    text: "Once",
  });
  assert.equal(repeated.status, 200);
  const again = await helper.browser("/api/ask", { id: "ask9", text: "Twice" });
  assert.equal(again.status, 200, "a retried post is idempotent");
  assert.equal((await helper.state()).questions.length, 1);
});
