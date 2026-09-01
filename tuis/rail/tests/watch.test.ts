// Watched repositories begin at their configured start time and share the
// same target-level row as account-wide attention.

import assert from "node:assert/strict";
import { test } from "node:test";

import { classifyTarget } from "../src/attention/classify.js";
import {
  defaultAttentionConfig,
  watchedRepositories,
} from "../src/attention/config.js";
import { buildQuery } from "../src/attention/github.js";
import type {
  GitHubComment,
  IssueTarget,
  PullRequestTarget,
} from "../src/attention/types.js";

const ME = "ryansaxe";
const FLOOR = "2026-08-01T00:00:00Z";
const config = defaultAttentionConfig();

const comment = (createdAt: string): GitHubComment => ({
  id: "comment-1",
  author: { login: "dana", kind: "user" },
  body: "A new comment",
  createdAt,
  url: "https://example.test/comment-1",
  viewerHasReacted: false,
});

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
  comments: [],
  reviewThreads: [],
  reviews: [],
  ...over,
});

function classify(
  target: PullRequestTarget | IssueTarget,
  watchedSince = FLOOR,
) {
  return classifyTarget(target, ME, config, {
    baselineAt: FLOOR,
    watchedSince,
  });
}

test("a target opened after the floor becomes one opened item", () => {
  const item = classify(watched());
  assert.deepEqual(
    item?.reasons.map((reason) => reason.kind),
    ["opened"],
  );
  assert.equal(item?.reasons[0]?.actor?.login, "dana");
  assert.equal(item?.targetKind, "pull_request");
});

test("a target opened before the floor stays silent", () => {
  const old = watched({ createdAt: "2026-07-01T00:00:00Z" });
  assert.equal(classify(old), null);
});

test("a repository with no watch floor is silent for opened activity", () => {
  assert.equal(
    classifyTarget(watched(), ME, config, { baselineAt: FLOOR }),
    null,
  );
});

test("your own work never creates an opened reason", () => {
  const mine = watched({ author: { login: ME, kind: "user" } });
  assert.equal(classify(mine), null);
});

test("bots stay suppressed unless allow-listed", () => {
  const bot = watched({ author: { login: "renovate[bot]", kind: "bot" } });
  assert.equal(classify(bot), null);
  const allowed = {
    ...config,
    actors: { allow: ["renovate[bot]"], ignore: [] },
  };
  assert.equal(
    classifyTarget(bot, ME, allowed, {
      baselineAt: FLOOR,
      watchedSince: FLOOR,
    })?.reasons[0]?.kind,
    "opened",
  );
});

test("a target found through account involvement is not an opened watch item", () => {
  const involved = watched({ searchSources: ["involved"] });
  assert.equal(classify(involved), null);
});

test("watching still starts now when a target also appears in account discovery", () => {
  const target = watched({
    searchSources: ["involved", "watched"],
    createdAt: "2026-07-01T00:00:00Z",
    comments: [comment("2026-08-10T00:00:00Z")],
  });
  assert.equal(classify(target, "2026-08-20T10:00:00Z"), null);
});

test("the opened row has a stable target id", () => {
  const first = classify(watched());
  const second = classify(watched());
  assert.equal(first?.id, "pull_request:someorg/infra#77");
  assert.equal(first?.id, second?.id);
  assert.equal(first?.activityKey, second?.activityKey);
});

test("a new comment on an existing watched target is reported after watch starts", () => {
  const target = watched({
    createdAt: "2026-07-01T00:00:00Z",
    comments: [comment("2026-08-20T10:01:00Z")],
  });
  const item = classify(target, "2026-08-20T10:00:00Z");
  assert.deepEqual(
    item?.reasons.map((reason) => reason.kind),
    ["comment"],
  );
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
  const item = classify(issue);
  assert.equal(item?.id, "issue:someorg/infra#481");
  assert.equal(item?.reasons[0]?.kind, "opened");
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

test("watching a repository covers pull requests and issues without reviewer requests", () => {
  const query = buildQuery(["a/b"]);
  assert.match(query, /watchedPrs0: search/);
  assert.match(query, /watchedIssues0: search/);
  assert.match(query, /-is:draft/);
  assert.ok(!query.includes("review-requested"));
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
