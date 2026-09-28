// The attention contract is target-level: one PR or issue row can carry
// comment, opened, and CI reasons without multiplying rows.

import assert from "node:assert/strict";
import { test } from "node:test";

import { classifyTarget } from "../src/attention/classify.js";
import { applyCiTransition } from "../src/attention/ci.js";
import { defaultAttentionConfig } from "../src/attention/config.js";
import { buildQuery, parseGithubResponse } from "../src/attention/github.js";
import type {
  AttentionItem,
  GitHubComment,
  GitHubReview,
  IssueTarget,
  PullRequestTarget,
} from "../src/attention/types.js";

const ME = "ryansaxe";
const FLOOR = "2026-08-20T00:00:00Z";
const config = defaultAttentionConfig();

const comment = (
  id: string,
  login: string,
  body = "hello",
  over: Partial<GitHubComment> = {},
): GitHubComment => ({
  id,
  author: { login, kind: login.endsWith("[bot]") ? "bot" : "user" },
  body,
  createdAt: new Date(
    Date.parse("2026-08-20T10:00:00Z") +
      Number(id.replace(/\D/g, "") || "0") * 60_000,
  ).toISOString(),
  url: `https://example.test/${id}`,
  viewerHasReacted: false,
  ...over,
});

const review = (
  id: string,
  state: GitHubReview["state"],
  submittedAt = "2026-08-20T10:01:00Z",
  body = "",
): GitHubReview => ({
  id,
  author: { login: "alice", kind: "user" },
  body,
  state,
  submittedAt,
  url: `https://example.test/${id}`,
});

const pr = (over: Partial<PullRequestTarget> = {}): PullRequestTarget => ({
  kind: "pull_request",
  repository: "me/repo",
  number: 1,
  title: "A pull request",
  body: "body",
  url: "https://example.test/pr/1",
  createdAt: "2026-08-19T10:00:00Z",
  updatedAt: "2026-08-20T10:00:00Z",
  isDraft: false,
  additions: 12,
  deletions: 3,
  changedFiles: 2,
  headSha: "sha-1",
  author: { login: ME, kind: "user" },
  ciState: "SUCCESS",
  failingChecks: [],
  searchSources: ["involved"],
  comments: [],
  reviewThreads: [],
  reviews: [],
  ...over,
});

const issue = (over: Partial<IssueTarget> = {}): IssueTarget => ({
  kind: "issue",
  repository: "me/repo",
  number: 9,
  title: "An issue",
  body: "body",
  url: "https://example.test/issue/9",
  createdAt: "2026-08-19T10:00:00Z",
  updatedAt: "2026-08-20T10:00:00Z",
  author: { login: ME, kind: "user" },
  labels: [],
  searchSources: ["involved"],
  comments: [],
  ...over,
});

function reasons(item: AttentionItem | null): string[] {
  return item?.reasons.map((reason) => reason.kind) ?? [];
}

for (const [label, make] of [
  ["pull request", pr],
  ["issue", issue],
] as const) {
  test(`${label}: authoring one alone produces no item`, () => {
    assert.equal(classifyTarget(make(), ME, config), null);
  });

  test(`${label}: owned external activity produces one comment row`, () => {
    const item = classifyTarget(
      make({ comments: [comment("c1", "alice")] }),
      ME,
      config,
    );
    assert.equal(item?.reasons.length, 1);
    assert.equal(item?.reasons[0]?.kind, "comment");
    assert.equal(item?.reasons[0]?.actor?.login, "alice");
    assert.equal(item?.targetKind, make().kind);
  });

  test(`${label}: your own reply clears the external activity`, () => {
    const item = classifyTarget(
      make({ comments: [comment("c1", "alice"), comment("c2", ME)] }),
      ME,
      config,
    );
    assert.equal(item, null);
  });

  test(`${label}: your reaction clears the external activity`, () => {
    const item = classifyTarget(
      make({
        comments: [comment("c1", "alice", "hi", { viewerHasReacted: true })],
      }),
      ME,
      config,
    );
    assert.equal(item, null);
  });

  test(`${label}: a later external response reopens the same target row`, () => {
    const item = classifyTarget(
      make({
        comments: [
          comment("c1", "alice"),
          comment("c2", ME),
          comment("c333", "bob"),
        ],
      }),
      ME,
      config,
    );
    assert.equal(item?.reasons.length, 1);
    assert.equal(item?.reasons[0]?.actor?.login, "bob");
  });

  test(`${label}: bots stay silent unless allow-listed`, () => {
    const withBot = make({ comments: [comment("c1", "dependabot[bot]")] });
    assert.equal(classifyTarget(withBot, ME, config), null);
    const allowed = {
      ...config,
      actors: { allow: ["dependabot[bot]"], ignore: [] },
    };
    assert.equal(classifyTarget(withBot, ME, allowed)?.reasons.length, 1);
  });

  test(`${label}: an untouched unrelated target is ignored`, () => {
    const theirs = make({
      author: { login: "carol", kind: "user" },
      comments: [comment("c1", "dave")],
    });
    assert.equal(classifyTarget(theirs, ME, config), null);
  });

  test(`${label}: direct participation makes later target activity relevant`, () => {
    const theirs = make({
      author: { login: "carol", kind: "user" },
      comments: [comment("c1", ME), comment("c2", "dave")],
    });
    const item = classifyTarget(theirs, ME, config);
    assert.deepEqual(reasons(item), ["comment"]);
    assert.equal(item?.reasons[0]?.actor?.login, "dave");
  });

  test(`${label}: a direct mention makes later target activity relevant`, () => {
    const theirs = make({
      author: { login: "carol", kind: "user" },
      comments: [
        comment("c1", "reviewer", "@ryansaxe please take a look"),
        comment("c2", "dave"),
      ],
    });
    assert.deepEqual(reasons(classifyTarget(theirs, ME, config)), ["comment"]);
  });

  test(`${label}: repeated polling keeps the target id and activity key stable`, () => {
    const target = make({ comments: [comment("c1", "alice")] });
    const first = classifyTarget(target, ME, config);
    const second = classifyTarget(target, ME, config);
    assert.equal(first?.id, `${make().kind}:me/repo#${make().number}`);
    assert.equal(first?.id, second?.id);
    assert.equal(first?.activityKey, second?.activityKey);
  });
}

test("a pull request merges all conversation and review-thread comments into one row", () => {
  const item = classifyTarget(
    pr({
      comments: [comment("c1", "alice")],
      reviewThreads: [
        {
          id: "thread-1",
          isResolved: true,
          comments: [comment("c2", "bob")],
        },
      ],
    }),
    ME,
    config,
  );
  assert.equal(item?.reasons.length, 1);
  assert.equal(item?.reasons[0]?.actor?.login, "bob");
});

test("an external formal review on your pull request becomes review attention", () => {
  const item = classifyTarget(
    pr({
      reviews: [review("review-1", "APPROVED", "2026-08-20T10:01:00Z", "LGTM")],
    }),
    ME,
    config,
    { baselineAt: FLOOR },
  );
  assert.deepEqual(reasons(item), ["review"]);
  assert.equal(item?.reasons[0]?.reviewState, "APPROVED");
  assert.equal(item?.reasons[0]?.actor?.login, "alice");
  assert.equal(item?.reasons[0]?.priority, "normal");
});

test("changes requested on your pull request has high priority", () => {
  const item = classifyTarget(
    pr({ reviews: [review("review-1", "CHANGES_REQUESTED")] }),
    ME,
    config,
    { baselineAt: FLOOR },
  );
  assert.equal(item?.reasons[0]?.reviewState, "CHANGES_REQUESTED");
  assert.equal(item?.reasons[0]?.priority, "high");
});

test("a comment-only formal review carries its summary", () => {
  const item = classifyTarget(
    pr({
      reviews: [
        review("review-1", "COMMENTED", "2026-08-20T10:01:00Z", "See note"),
      ],
    }),
    ME,
    config,
    { baselineAt: FLOOR },
  );
  assert.equal(item?.reasons[0]?.reviewState, "COMMENTED");
  assert.equal(item?.reasons[0]?.summary, "Submitted review: See note");
});

test("formal reviews are limited to pull requests authored by the viewer", () => {
  const item = classifyTarget(
    pr({
      author: { login: "carol", kind: "user" },
      reviews: [review("review-1", "APPROVED")],
    }),
    ME,
    config,
  );
  assert.equal(item, null);
});

test("dismissed and historical formal reviews stay out of the inbox", () => {
  assert.equal(
    classifyTarget(
      pr({ reviews: [review("review-1", "DISMISSED")] }),
      ME,
      config,
      { baselineAt: FLOOR },
    ),
    null,
  );
  assert.equal(
    classifyTarget(
      pr({
        reviews: [review("review-2", "APPROVED", "2026-08-19T10:00:00Z")],
      }),
      ME,
      config,
      { baselineAt: FLOOR },
    ),
    null,
  );
  assert.equal(
    classifyTarget(
      pr({
        reviews: [
          {
            ...review("review-3", "APPROVED"),
            author: { login: ME, kind: "user" },
          },
        ],
      }),
      ME,
      config,
    ),
    null,
  );
});

test("a watched target can carry opened and comment reasons in one row", () => {
  const target = pr({
    repository: "someorg/infra",
    number: 77,
    author: { login: "dana", kind: "user" },
    createdAt: "2026-08-20T10:00:00Z",
    searchSources: ["watched"],
    comments: [comment("c1", "alice")],
  });
  const item = classifyTarget(target, ME, config, {
    baselineAt: "2026-08-20T10:00:00Z",
    watchedSince: "2026-08-20T10:00:00Z",
  });
  assert.deepEqual(reasons(item), ["comment", "opened"]);
  assert.equal(item?.id, "pull_request:someorg/infra#77");
});

test("watching a repository reports comments on an existing target only after watch starts", () => {
  const target = pr({
    repository: "someorg/infra",
    author: { login: "dana", kind: "user" },
    createdAt: "2026-07-01T10:00:00Z",
    searchSources: ["watched"],
    comments: [
      comment("c1", "alice", "old", {
        createdAt: "2026-07-01T11:00:00Z",
      }),
      comment("c2", "bob", "new", {
        createdAt: "2026-08-20T10:01:00Z",
      }),
    ],
  });
  const item = classifyTarget(target, ME, config, {
    baselineAt: "2026-08-01T00:00:00Z",
    watchedSince: "2026-08-20T10:00:00Z",
  });
  assert.deepEqual(reasons(item), ["comment"]);
  assert.equal(item?.reasons[0]?.actor?.login, "bob");
});

test("a watched target opened before the watch floor stays silent without new activity", () => {
  const target = pr({
    repository: "someorg/infra",
    author: { login: "dana", kind: "user" },
    createdAt: "2026-07-01T10:00:00Z",
    searchSources: ["watched"],
  });
  assert.equal(
    classifyTarget(target, ME, config, {
      baselineAt: "2026-08-01T00:00:00Z",
      watchedSince: "2026-08-20T10:00:00Z",
    }),
    null,
  );
});

test("a watched target opened by the viewer is not an opened reason", () => {
  const target = pr({
    repository: "someorg/infra",
    createdAt: "2026-08-20T10:00:00Z",
    searchSources: ["watched"],
  });
  assert.equal(
    classifyTarget(target, ME, config, {
      watchedSince: "2026-08-01T00:00:00Z",
    }),
    null,
  );
});

test("a watched draft is not an opened reason", () => {
  const target = pr({
    repository: "someorg/infra",
    author: { login: "dana", kind: "user" },
    createdAt: "2026-08-20T10:00:00Z",
    isDraft: true,
    searchSources: ["watched"],
  });
  assert.equal(
    classifyTarget(target, ME, config, {
      watchedSince: "2026-08-01T00:00:00Z",
    }),
    null,
  );
});

test("CI produces a reason, not a second target item", () => {
  const failing = pr({
    ciState: "FAILURE",
    failingChecks: ["lint", "typecheck"],
  });
  const { reason } = applyCiTransition(failing, undefined, ME, config);
  assert.equal(reason?.kind, "ci");
  assert.match(reason?.summary ?? "", /lint, typecheck/);
});

test("a non-definitive rollup is not a red alert", () => {
  for (const state of ["PENDING", "NEUTRAL", "EXPECTED", "UNKNOWN"] as const) {
    const { reason } = applyCiTransition(
      pr({ ciState: state }),
      undefined,
      ME,
      config,
    );
    assert.equal(reason, null, `${state} must not alert`);
  }
});

test("a steady red CI keeps the same reason after the first alert", () => {
  const failing = pr({ ciState: "FAILURE", failingChecks: ["lint"] });
  const first = applyCiTransition(failing, undefined, ME, config);
  const second = applyCiTransition(failing, first.memory, ME, config);
  assert.equal(first.newlyRed, true);
  assert.equal(second.newlyRed, false);
  assert.equal(first.reason?.id, second.reason?.id);
});

test("a new head commit creates a new CI activity revision", () => {
  const first = applyCiTransition(
    pr({ ciState: "FAILURE", failingChecks: ["lint"] }),
    undefined,
    ME,
    config,
  );
  const second = applyCiTransition(
    pr({
      ciState: "FAILURE",
      failingChecks: ["lint"],
      headSha: "sha-2",
    }),
    first.memory,
    ME,
    config,
  );
  assert.equal(second.newlyRed, true);
  assert.notEqual(first.reason?.id, second.reason?.id);
});

test("an old red CI state is suppressed by the initial baseline", () => {
  const failing = pr({
    ciState: "FAILURE",
    updatedAt: "2026-08-20T10:00:00Z",
  });
  const first = applyCiTransition(
    failing,
    undefined,
    ME,
    config,
    "2026-08-21T00:00:00Z",
  );
  const second = applyCiTransition(
    failing,
    first.memory,
    ME,
    config,
    "2026-08-21T00:00:00Z",
  );
  assert.equal(first.reason, null);
  assert.equal(second.reason, null);
  assert.equal(first.memory.alerted, false);
});

test("CI is restricted to the viewer's own pull requests", () => {
  const failing = pr({
    author: { login: "alice", kind: "user" },
    ciState: "FAILURE",
  });
  assert.equal(applyCiTransition(failing, undefined, ME, config).reason, null);
});

test("the discovery query has no reviewer-request search", () => {
  const query = buildQuery([]);
  assert.ok(!query.includes("review-requested"));
  assert.ok(!query.includes("prsRequested"));
});

test("only failing checks are extracted from the rollup", () => {
  const response = JSON.stringify({
    data: {
      viewer: { login: ME },
      rateLimit: { cost: 1, remaining: 100, resetAt: "2026-08-20T11:00:00Z" },
      prsInvolved: {
        nodes: [
          {
            number: 3,
            title: "t",
            body: "b",
            url: "u",
            createdAt: "2026-08-19T10:00:00Z",
            updatedAt: "2026-08-20T10:00:00Z",
            isDraft: false,
            headRefOid: "sha",
            author: { login: ME, __typename: "User" },
            repository: { nameWithOwner: "me/repo" },
            reviewThreads: { nodes: [] },
            comments: { nodes: [] },
            statusCheckRollup: {
              state: "FAILURE",
              contexts: {
                nodes: [
                  {
                    __typename: "CheckRun",
                    name: "lint",
                    conclusion: "FAILURE",
                  },
                  {
                    __typename: "CheckRun",
                    name: "build",
                    conclusion: "SUCCESS",
                  },
                  {
                    __typename: "CheckRun",
                    name: "flaky",
                    conclusion: "CANCELLED",
                  },
                  {
                    __typename: "CheckRun",
                    name: "extra",
                    conclusion: "SKIPPED",
                  },
                  {
                    __typename: "StatusContext",
                    context: "deploy",
                    state: "ERROR",
                  },
                ],
              },
            },
          },
        ],
      },
      issuesInvolved: { nodes: [] },
    },
  });
  const parsed = parseGithubResponse(response, 1);
  const target = parsed.targets[0];
  assert.equal(target?.kind, "pull_request");
  assert.deepEqual(
    target?.kind === "pull_request" ? target.failingChecks : null,
    ["lint", "deploy"],
  );
});

test("issues parse into targets alongside pull requests", () => {
  const response = JSON.stringify({
    data: {
      viewer: { login: ME },
      rateLimit: { cost: 1, remaining: 100, resetAt: "2026-08-20T11:00:00Z" },
      prsInvolved: { nodes: [] },
      issuesInvolved: {
        nodes: [
          {
            number: 42,
            title: "An issue",
            body: "b",
            url: "u",
            createdAt: "2026-08-19T10:00:00Z",
            updatedAt: "2026-08-20T10:00:00Z",
            author: { login: "alice", __typename: "User" },
            repository: { nameWithOwner: "me/repo" },
            comments: { nodes: [] },
          },
        ],
      },
    },
  });
  const parsed = parseGithubResponse(response, 1);
  assert.equal(parsed.targets.length, 1);
  assert.equal(parsed.targets[0]?.kind, "issue");
  assert.equal(parsed.targets[0]?.number, 42);
});
