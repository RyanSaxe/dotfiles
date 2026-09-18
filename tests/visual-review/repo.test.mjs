import assert from "node:assert/strict";
import fs from "node:fs/promises";
import path from "node:path";
import test from "node:test";
import { serve } from "../../ai-harness/skills/visual-review/scripts/session.mjs";
import {
  createLargeRepository,
  createSampleRepository,
  inspect,
  removeAll,
  temporaryDirectory,
} from "./fixtures/repo.mjs";

/** Start a helper on a repository and hand the test a fetch bound to it. */
async function open(repo) {
  const sessionDir = await temporaryDirectory("session");
  const session = await serve(sessionDir, { repo });
  const get = async (route) => {
    const response = await fetch(session.origin + route);
    const body = await response.json().catch(() => ({ error: "not JSON" }));
    return { status: response.status, body };
  };
  return {
    ...session,
    sessionDir,
    get,
    async stop() {
      await session.close();
      await removeAll(sessionDir);
    },
  };
}

test("serves committed files at any ref and reports the repository", async (t) => {
  const repo = await createSampleRepository();
  const helper = await open(repo.root);
  t.after(async () => {
    await helper.stop();
    await removeAll(repo.root, repo.origin);
  });

  assert.equal(helper.repo.ref, "main");
  assert.equal(helper.repo.refType, "branch");
  assert.equal(helper.repo.root, await fs.realpath(repo.root));

  const current = await helper.get("/repo/file?path=src/client.py");
  assert.equal(current.status, 200);
  assert.match(current.body.content, /BREAKER = True/);
  assert.equal(current.body.truncated, false);

  const original = await helper.get(
    `/repo/file?path=src/client.py&ref=${repo.first}`,
  );
  assert.equal(original.status, 200);
  assert.doesNotMatch(original.body.content, /BREAKER/);
  assert.notEqual(original.body.sha, current.body.sha);
});

test("lists one directory at a time, directories first", async (t) => {
  const repo = await createSampleRepository();
  const helper = await open(repo.root);
  t.after(async () => {
    await helper.stop();
    await removeAll(repo.root, repo.origin);
  });

  const root = await helper.get("/repo/tree");
  assert.deepEqual(
    root.body.entries.map((entry) => entry.name),
    ["assets", "src", "big.txt", "README.md"],
  );
  assert.equal(root.body.entries[0].type, "directory");

  const source = await helper.get("/repo/tree?path=src");
  assert.deepEqual(
    source.body.entries.map((entry) => `${entry.type}:${entry.name}`),
    ["directory:ledger", "file:client.py", "file:gateway.py"],
    "a tree lists its own entries, never the files beneath its subdirectories",
  );
});

test("searches paths case-insensitively and caps the result count", async (t) => {
  const repo = await createSampleRepository();
  const helper = await open(repo.root);
  t.after(async () => {
    await helper.stop();
    await removeAll(repo.root, repo.origin);
  });

  const hits = await helper.get("/repo/paths?q=CLIENT");
  assert.deepEqual(
    hits.body.matches.map((match) => match.path),
    ["src/client.py"],
  );
  assert.deepEqual(hits.body.matches[0].positions, [4, 5, 6, 7, 8, 9]);
  assert.equal(hits.body.total, 1);
  assert.equal(hits.body.tracked, 6, "every tracked file at the ref");

  const capped = await helper.get("/repo/paths?q=.py&limit=2");
  assert.equal(capped.body.matches.length, 2);
  assert.equal(capped.body.total, 3, "total counts every match, not the page");

  const beyondCap = await helper.get("/repo/paths?q=.&limit=5000");
  assert.ok(beyondCap.body.matches.length <= 200);
});

test("answers existence for files and directories from the index", async (t) => {
  const repo = await createSampleRepository();
  const helper = await open(repo.root);
  t.after(async () => {
    await helper.stop();
    await removeAll(repo.root, repo.origin);
  });

  assert.deepEqual((await helper.get("/repo/exists?path=src/client.py")).body, {
    path: "src/client.py",
    ref: "main",
    exists: true,
    type: "file",
  });
  assert.equal(
    (await helper.get("/repo/exists?path=src/ledger")).body.type,
    "directory",
  );
  assert.equal(
    (await helper.get("/repo/exists?path=src/missing.py")).body.exists,
    false,
  );
});

test("diffs one file between two refs", async (t) => {
  const repo = await createSampleRepository();
  const helper = await open(repo.root);
  t.after(async () => {
    await helper.stop();
    await removeAll(repo.root, repo.origin);
  });

  const changed = await helper.get(
    `/repo/diff?base=${repo.first}&head=${repo.second}&path=src/client.py`,
  );
  assert.match(changed.body.patch, /^diff --git a\/src\/client\.py/m);
  assert.match(changed.body.patch, /\+ {4}BREAKER = True/);

  const unchanged = await helper.get(
    `/repo/diff?base=${repo.first}&head=${repo.second}&path=src/gateway.py`,
  );
  assert.equal(unchanged.body.patch, "", "an unchanged file diffs to nothing");
});

test("fetches a pull request head on first use and reuses the ref after", async (t) => {
  const repo = await createSampleRepository();
  const helper = await open(repo.root);
  t.after(async () => {
    await helper.stop();
    await removeAll(repo.root, repo.origin);
  });

  const before = await inspect(repo.root, [
    "rev-parse",
    "--verify",
    "--quiet",
    "refs/visual-review/pr/7",
  ]).catch(() => null);
  assert.equal(before, null, "the ref does not exist before the first request");

  const first = await helper.get("/repo/file?path=src/client.py&ref=pr/7");
  assert.equal(first.status, 200);
  assert.match(first.body.content, /ATTEMPTS = 7/);
  assert.equal(first.body.sha, repo.pull);

  assert.equal(
    await inspect(repo.root, ["rev-parse", "refs/visual-review/pr/7"]),
    repo.pull,
  );
  assert.equal(
    await inspect(repo.root, ["branch", "--list"]),
    "* main",
    "the fetch leaves the repository's branches alone",
  );

  const again = await helper.get("/repo/tree?path=src&ref=pr/7");
  assert.equal(again.status, 200);

  const missing = await helper.get("/repo/file?path=src/client.py&ref=pr/9999");
  assert.equal(
    missing.status,
    502,
    "a pull request that cannot be fetched is a gateway error",
  );
});

test("refuses refs and paths that could reach outside the repository", async (t) => {
  const repo = await createSampleRepository();
  const helper = await open(repo.root);
  t.after(async () => {
    await helper.stop();
    await removeAll(repo.root, repo.origin);
  });

  const cases = [
    ["/repo/file?path=README.md&ref=no-such-ref", 404],
    ["/repo/file?path=../outside.txt", 400],
    ["/repo/file?path=/etc/passwd", 400],
    ["/repo/file?path=src/..%2f..%2fetc/passwd", 400],
    ["/repo/file?path=src%5Cclient.py", 400],
    ["/repo/file?path=README.md&ref=-x", 400],
    ["/repo/file?path=-README.md", 400],
    ["/repo/file?path=src/missing.py", 404],
    ["/repo/tree?path=src&ref=../../etc", 404],
    ["/repo/nothing", 404],
  ];
  for (const [route, status] of cases) {
    const result = await helper.get(route);
    assert.equal(result.status, status, `${route} should answer ${status}`);
  }
});

test("refuses binary blobs and truncates a file past the ceiling", async (t) => {
  const repo = await createSampleRepository();
  const helper = await open(repo.root);
  t.after(async () => {
    await helper.stop();
    await removeAll(repo.root, repo.origin);
  });

  const binary = await helper.get("/repo/file?path=assets/logo.bin");
  assert.equal(binary.status, 415);

  const large = await helper.get("/repo/file?path=big.txt");
  assert.equal(large.status, 200);
  assert.equal(large.body.truncated, true);
  assert.equal(large.body.content.length, 2 * 1024 * 1024);
});

test("caches every answer it served so export needs no repository", async (t) => {
  const repo = await createSampleRepository();
  const helper = await open(repo.root);
  t.after(async () => {
    await helper.stop();
    await removeAll(repo.root, repo.origin);
  });

  await helper.get("/repo/file?path=src/client.py");
  await helper.get("/repo/tree?path=src");
  await helper.get(
    `/repo/diff?base=${repo.first}&head=${repo.second}&path=src/client.py`,
  );

  const cacheDir = path.join(helper.sessionDir, "repo-cache");
  const entries = await Promise.all(
    (await fs.readdir(cacheDir)).map(async (name) =>
      JSON.parse(await fs.readFile(path.join(cacheDir, name), "utf8")),
    ),
  );
  const keys = entries.map((entry) => entry.key.split(":")[0]);
  assert.deepEqual(new Set(keys), new Set(["index", "file", "tree", "diff"]));
  const file = entries.find((entry) => entry.key.startsWith("file:"));
  assert.match(file.value.content, /BREAKER/);
  assert.match(file.key, new RegExp(`^file:${repo.second}:src/client\\.py$`));
});

test("stays lazy and blind to the working tree in a 100,000 file repository", async (t) => {
  const repo = await createLargeRepository();
  const helper = await open(repo.root);
  t.after(async () => {
    await helper.stop();
    await removeAll(repo.root);
  });

  const indexStart = Date.now();
  const firstFilter = await helper.get("/repo/paths?q=file000042");
  const indexMs = Date.now() - indexStart;
  assert.equal(firstFilter.status, 200);
  assert.equal(firstFilter.body.total, 1);

  const filterStart = Date.now();
  const filtered = await helper.get("/repo/paths?q=dir0500/file&limit=200");
  const filterMs = Date.now() - filterStart;
  assert.equal(filtered.body.matches.length, 100);

  const treeStart = Date.now();
  const tree = await helper.get("/repo/tree?path=pkg");
  const treeMs = Date.now() - treeStart;
  assert.equal(tree.body.entries.length, 1000);
  assert.ok(
    tree.body.entries.every((entry) => entry.type === "directory"),
    "listing pkg returns its directories, not the 100,000 files beneath them",
  );

  // Wall clock varies by machine, so these ceilings are loose enough to stay
  // green under load and tight enough to catch a walk that stopped being lazy.
  t.diagnostic(
    `index+filter ${indexMs} ms, cached filter ${filterMs} ms, tree ${treeMs} ms`,
  );
  assert.ok(indexMs < 20_000, `index build took ${indexMs} ms`);
  assert.ok(filterMs < 2_000, `cached filter took ${filterMs} ms`);
  assert.ok(treeMs < 2_000, `directory listing took ${treeMs} ms`);

  for (const route of [
    "/repo/tree",
    "/repo/paths?q=.venv&limit=200",
    "/repo/paths?q=module0&limit=200",
  ]) {
    const result = await helper.get(route);
    const text = JSON.stringify(result.body);
    assert.doesNotMatch(
      text,
      /\.venv/,
      `${route} exposed an ignored directory`,
    );
    assert.doesNotMatch(text, /module0/, `${route} exposed an ignored file`);
  }
  assert.equal(
    (await helper.get("/repo/file?path=.venv/lib/module1.py")).status,
    404,
    "an ignored file is not servable even by exact path",
  );
});
