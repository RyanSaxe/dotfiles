// Watched repositories: hear about new pull requests and issues in a
// repository even when you are not involved in it.

import assert from "node:assert/strict";
import { test } from "node:test";

import { classifyOpened } from "../src/attention/classify.js";
import {
  defaultAttentionConfig,
  watchedRepositories,
} from "../src/attention/config.js";
import { buildQuery } from "../src/attention/github.js";
import type { IssueTarget, PullRequestTarget } from "../src/attention/types.js";

const ME = "ryansaxe";
const FLOOR = "2026-08-01T00:00:00Z";
const config = defaultAttentionConfig();

const watched = (over: Partial<PullRequestTarget> = {}): PullRequestTarget => ({
  kind: "pull_request",
  repository: "someorg/infra",
  number: 77,
  title: "Rotate staging credentials",
  body: "body",
  url: "https://example.test/pr/77",
  createdAt: "2026-08-20T10:00:00Z",
  updatedAt: "2026-08-20T10:00:00Z",
  isDraft: false,
  additions: 41,
  deletions: 12,
  changedFiles: 3,
  headSha: "sha",
  author: { login: "dana", kind: "user" },
  ciState: "SUCCESS",
  failingChecks: [],
  searchSources: ["watched"],
  reviewRequested: false,
  reviewRequestFingerprint: "",
  comments: [],
  reviewThreads: [],
  ...over,
});

test("a target opened after the floor becomes an item", () => {
  const item = classifyOpened(watched(), ME, config, FLOOR);
  assert.equal(item?.kind, "opened");
  assert.equal(item?.actor?.login, "dana");
  assert.equal(item?.targetKind, "pull_request");
});

test("a target opened before the floor stays silent", () => {
  // Adding a repository must not dump its backlog.
  const old = watched({ createdAt: "2026-07-01T00:00:00Z" });
  assert.equal(classifyOpened(old, ME, config, FLOOR), null);
});

test("a repository with no floor yet is silent", () => {
  assert.equal(classifyOpened(watched(), ME, config, undefined), null);
});

test("your own work never notifies you", () => {
  const mine = watched({ author: { login: ME, kind: "user" } });
  assert.equal(classifyOpened(mine, ME, config, FLOOR), null);
});

test("bots stay suppressed unless allow-listed", () => {
  const bot = watched({ author: { login: "renovate[bot]", kind: "bot" } });
  assert.equal(classifyOpened(bot, ME, config, FLOOR), null);
  const allowed = {
    ...config,
    actors: { allow: ["renovate[bot]"], ignore: [] },
  };
  assert.notEqual(classifyOpened(bot, ME, allowed, FLOOR), null);
});

test("a target you merely happen to be involved in is not an opened item", () => {
  const involved = watched({ searchSources: ["involved"] });
  assert.equal(classifyOpened(involved, ME, config, FLOOR), null);
});

test("the id is stable, so a persisting target keeps one item", () => {
  const first = classifyOpened(watched(), ME, config, FLOOR);
  const second = classifyOpened(watched(), ME, config, FLOOR);
  assert.equal(first?.id, second?.id);
  assert.equal(first?.id, "opened:someorg/infra#77");
});

test("issues are watched the same way", () => {
  const issue: IssueTarget = {
    kind: "issue",
    repository: "someorg/infra",
    number: 481,
    title: "Deploy misses rotated secret",
    body: "body",
    url: "https://example.test/issue/481",
    createdAt: "2026-08-20T10:00:00Z",
    updatedAt: "2026-08-20T10:00:00Z",
    author: { login: "erin", kind: "user" },
    labels: ["bug"],
    searchSources: ["watched"],
    comments: [],
  };
  const item = classifyOpened(issue, ME, config, FLOOR);
  assert.equal(item?.targetKind, "issue");
});

test("ATTENTION_WATCH parses a space-separated list", () => {
  assert.deepEqual(watchedRepositories({ ATTENTION_WATCH: "a/b c/d" }), [
    "a/b",
    "c/d",
  ]);
  assert.deepEqual(
    watchedRepositories({ ATTENTION_WATCH: " a/b,  c/d \n e/f " }),
    ["a/b", "c/d", "e/f"],
  );
  assert.deepEqual(watchedRepositories({}), []);
  assert.deepEqual(watchedRepositories({ ATTENTION_WATCH: "   " }), []);
});

test("a duplicate repository is listed once", () => {
  assert.deepEqual(watchedRepositories({ ATTENTION_WATCH: "a/b a/b c/d" }), [
    "a/b",
    "c/d",
  ]);
});

test("a malformed entry is a literal, actionable error", () => {
  assert.throws(
    () => watchedRepositories({ ATTENTION_WATCH: "a/b notarepo c/d" }),
    /expected space-separated "owner\/name" entries, got notarepo/,
  );
});

test("watching a repository covers its pull requests and its issues", () => {
  const query = buildQuery(["a/b"]);
  assert.match(query, /watchedPrs0: search/);
  assert.match(query, /watchedIssues0: search/);
  assert.match(query, /-is:draft/);
  const prSearch = query.slice(
    query.indexOf("watchedPrs0"),
    query.indexOf("watchedIssues0"),
  );
  assert.match(prSearch, /repo:a\/b/);
});

test("more than twenty repositories chunk into extra searches", () => {
  const many = Array.from({ length: 25 }, (_, i) => `org/repo${i}`);
  const query = buildQuery(many);
  assert.match(query, /watchedPrs0: search/);
  assert.match(query, /watchedPrs1: search/);
});

test("no watch list means no extra searches", () => {
  const query = buildQuery([]);
  assert.ok(!query.includes("watchedPrs"));
  assert.ok(!query.includes("watchedIssues"));
});
