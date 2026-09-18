import assert from "node:assert/strict";
import fs from "node:fs/promises";
import path from "node:path";
import test from "node:test";
import {
  buildExport,
  exportName,
  serve,
} from "../../ai-harness/skills/visual-review/scripts/session.mjs";
import {
  request,
  useEmbeddedData,
} from "../../ai-harness/skills/visual-review/assets/transport.mjs";
import {
  createSampleRepository,
  removeAll,
  temporaryDirectory,
} from "./fixtures/repo.mjs";

/** Read the session an exported file carries. */
function embedded(html) {
  const match = html.match(
    /<script[^>]*id="session-data"[^>]*>([\s\S]*?)<\/script>/i,
  );
  assert.ok(match, "an export carries its session as embedded data");
  return JSON.parse(match[1].replaceAll("\\u003c", "<"));
}

test("names the file after the repository and the day", () => {
  const when = new Date("2026-09-17T18:00:00Z");
  assert.equal(
    exportName({ name: "acme/payments" }, when),
    "visual-review-acme-payments-2026-09-17.html",
  );
  assert.equal(
    exportName({ name: "" }, when),
    "visual-review-repository-2026-09-17.html",
  );
});

test("refuses to write a file carrying the session's secrets", () => {
  const shell =
    '<script id="session-config">{}</script><script id="session-data">null</script>';
  const build = (secrets) =>
    buildExport({
      shell,
      state: { sessionId: "s", questions: [] },
      pages: { "q/a": "a secret-token lives here" },
      repo: { name: "r", ref: "main" },
      refs: {},
      cache: {},
      secrets,
    });
  assert.ok(build(["not-present"]));
  assert.throws(() => build(["secret-token"]), /secrets/);
});

test("escapes the embedded JSON so it cannot close its own script", () => {
  const html = buildExport({
    shell:
      '<script id="session-config">{}</script><script id="session-data">null</script>',
    state: { sessionId: "s", questions: [] },
    pages: { "q/a": "</script><script>alert(1)</script>" },
    repo: { name: "r", ref: "main" },
    refs: {},
    cache: {},
  });
  assert.ok(
    !html.includes("<script>alert(1)"),
    "page content cannot break out of the data block",
  );
  assert.ok(html.includes("\\u003c/script"));
  assert.equal(
    embedded(html).pages["q/a"],
    "</script><script>alert(1)</script>",
  );
});

test("keeps repository content that mentions an asset path", () => {
  const shell =
    '<link rel="stylesheet" href="/assets/app.css" />' +
    '<script type="module" src="/assets/app.js"></script>' +
    '<script id="session-config">{}</script><script id="session-data">null</script>';
  const html = buildExport({
    shell,
    state: { sessionId: "s", questions: [] },
    // A repository may legitimately contain the string the check looks for.
    pages: { "q/a": 'import x from "../assets/choices.mjs";' },
    repo: { name: "r", ref: "main" },
    refs: {},
    cache: {},
    css: "body{}",
    moduleUrl: "data:text/javascript;base64,AA==",
  });
  assert.ok(!html.includes('href="/assets/app.css"'));
  assert.ok(!html.includes('src="/assets/app.js"'));
  assert.match(
    embedded(html).pages["q/a"],
    /assets\/choices\.mjs/,
    "the page's own references are replaced; quoted code is left alone",
  );
});

test("carries the whole session and everything it served", async (t) => {
  const repo = await createSampleRepository();
  const sessionDir = await temporaryDirectory("session");
  const session = await serve(sessionDir, { repo: repo.root });
  const { token } = JSON.parse(
    await fs.readFile(path.join(sessionDir, "connection.json"), "utf8"),
  );
  t.after(async () => {
    await session.close();
    await removeAll(sessionDir, repo.root, repo.origin);
  });

  const browser = (route, body) =>
    fetch(session.origin + route, {
      method: "POST",
      headers: { "Content-Type": "application/json", Origin: session.origin },
      body: JSON.stringify({ sessionId: session.sessionId, ...body }),
    });
  const agent = (body) =>
    fetch(session.origin + "/agent/action", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        authorization: `Bearer ${token}`,
      },
      body: JSON.stringify({ sessionId: session.sessionId, ...body }),
    }).then((response) => response.json());

  await browser("/api/ask", { id: "q1", text: "How does a charge work?" });
  await agent({
    action: "plan",
    question: "q1",
    title: "Charges",
    pages: "overview=Overview,change=What changed",
  });
  await agent({
    action: "page",
    question: "q1",
    id: "overview",
    markdown: "# Overview\n\nThe client is `src/client.py`.\n",
  });
  await agent({
    action: "page",
    question: "q1",
    id: "change",
    markdown:
      "```diff main..pr/7 src/client.py\nWhat the pull request does.\n```\n",
  });
  await agent({ action: "done", question: "q1" });

  // Whatever the reader looked at is what the export can show later.
  for (const route of [
    "/repo/file?path=src/client.py",
    "/repo/tree?path=src",
    `/repo/diff?base=main&head=pr/7&path=src/client.py`,
    "/repo/paths?q=client",
  ])
    assert.equal((await fetch(session.origin + route)).status, 200, route);

  const report = await agent({ action: "export" });
  const html = await fs.readFile(report.path, "utf8");
  assert.equal(report.name, exportName(session.repo));
  assert.ok(report.bytes > 0);
  assert.equal(report.warning, null);

  assert.ok(!html.includes(token), "the agent token never reaches the file");
  assert.ok(
    !html.includes(sessionDir),
    "the session directory never reaches the file",
  );

  const data = embedded(html);
  assert.equal(data.repo.name, session.repo.name);
  assert.ok(
    !Object.keys(data.cache).some((key) => key.startsWith("index:")),
    "the path index stays behind; the export knows only what it served",
  );
  assert.deepEqual(Object.keys(data.pages).sort(), [
    "q1/change",
    "q1/overview",
  ]);
  assert.match(data.pages["q1/overview"], /The client is/);
  assert.equal(data.state.stage, "exported");
  assert.equal(data.state.pending, 0);
  assert.equal(
    data.refs["pr/7"],
    repo.pull,
    "a pull request ref resolves in the export too",
  );

  // The page answers its own questions from here, with no helper running.
  useEmbeddedData(data);
  t.after(() => useEmbeddedData(null));

  const file = await (
    await request("/repo/file?path=src/client.py&ref=main")
  ).json();
  assert.match(file.content, /BREAKER = True/);

  const diff = await (
    await request("/repo/diff?base=main&head=pr/7&path=src/client.py")
  ).json();
  assert.match(diff.patch, /ATTEMPTS = 7/);

  const page = await (
    await request("/api/page?question=q1&id=overview")
  ).text();
  assert.match(page, /The client is/);

  // Quick open reaches only the files the session served.
  const found = await (await request("/repo/paths?q=.")).json();
  assert.deepEqual(
    found.matches.map((match) => match.path),
    ["src/client.py"],
    "a file nobody opened is absent from the palette",
  );
  assert.equal(found.tracked, 1);

  const client = await (
    await request("/repo/exists?path=src/client.py")
  ).json();
  assert.equal(client.type, "file");
  const ledger = await (await request("/repo/exists?path=src/ledger")).json();
  assert.equal(ledger.exists, false, "an unserved directory makes no chip");

  const tree = await (await request("/repo/tree?path=src")).json();
  assert.deepEqual(
    tree.entries.map((entry) => entry.name),
    ["ledger", "client.py", "gateway.py"],
    "a directory the session listed is still listed",
  );
  assert.equal(
    (await request("/repo/tree?path=assets")).status,
    404,
    "a directory nobody listed is not invented from an index",
  );

  await assert.rejects(
    request("/api/ask", { method: "POST" }),
    /cannot ask questions/,
    "an exported session refuses to pretend it can reach an agent",
  );
});
