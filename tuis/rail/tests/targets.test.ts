// The locked attention semantics, exercised against fixtures. One classifier
// serves pull requests and issues, so each rule is asserted on both.

import assert from "node:assert/strict";
import { test } from "node:test";

import { classifyTarget } from "../src/attention/classify.js";
import { applyCiTransition } from "../src/attention/ci.js";
import { defaultAttentionConfig } from "../src/attention/config.js";
import { parseGithubResponse } from "../src/attention/github.js";
import type {
  GitHubComment,
  IssueTarget,
  PullRequestTarget,
} from "../src/attention/types.js";

const ME = "ryansaxe";
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
  // Ordering matters: "your own reply clears it" depends on which comment
  // is genuinely last, so the id's number drives the timestamp.
  createdAt: new Date(
    Date.parse("2026-08-20T10:00:00Z") +
      Number(id.replace(/\D/g, "") || "0") * 60_000,
  ).toISOString(),
  url: `https://example.test/${id}`,
  viewerHasReacted: false,
  ...over,
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
  reviewRequested: false,
  reviewRequestFingerprint: "",
  comments: [],
  reviewThreads: [],
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

for (const [label, make] of [
  ["pull request", pr],
  ["issue", issue],
] as const) {
  test(`${label}: authoring one alone produces no item`, () => {
    assert.deepEqual(classifyTarget(make(), ME, config), []);
  });

  test(`${label}: someone else responding produces one item`, () => {
    const items = classifyTarget(
      make({ comments: [comment("c1", "alice")] }) as never,
      ME,
      config,
    );
    assert.equal(items.length, 1);
    assert.equal(items[0]?.actor?.login, "alice");
    assert.equal(items[0]?.targetKind, make().kind);
  });

  test(`${label}: your own reply clears it`, () => {
    const items = classifyTarget(
      make({ comments: [comment("c1", "alice"), comment("c2", ME)] }) as never,
      ME,
      config,
    );
    assert.deepEqual(items, []);
  });

  test(`${label}: your reaction clears it`, () => {
    const items = classifyTarget(
      make({
        comments: [comment("c1", "alice", "hi", { viewerHasReacted: true })],
      }) as never,
      ME,
      config,
    );
    assert.deepEqual(items, []);
  });

  test(`${label}: a later external response reopens it`, () => {
    const items = classifyTarget(
      make({
        comments: [
          comment("c1", "alice"),
          comment("c2", ME),
          comment("c333", "bob"),
        ],
      }) as never,
      ME,
      config,
    );
    assert.equal(items.length, 1);
    assert.equal(items[0]?.actor?.login, "bob");
  });

  test(`${label}: bots stay silent unless allow-listed`, () => {
    const withBot = make({ comments: [comment("c1", "dependabot[bot]")] });
    assert.deepEqual(classifyTarget(withBot as never, ME, config), []);
    const allowed = {
      ...config,
      actors: { allow: ["dependabot[bot]"], ignore: [] },
    };
    assert.equal(classifyTarget(withBot as never, ME, allowed).length, 1);
  });

  test(`${label}: a stranger's thread you never touched is ignored`, () => {
    const theirs = make({
      author: { login: "carol", kind: "user" },
      comments: [comment("c1", "dave")],
    });
    assert.deepEqual(classifyTarget(theirs as never, ME, config), []);
  });

  test(`${label}: repeated polling yields the same id`, () => {
    const target = make({ comments: [comment("c1", "alice")] });
    const first = classifyTarget(target as never, ME, config);
    const second = classifyTarget(target as never, ME, config);
    assert.equal(first[0]?.id, second[0]?.id);
  });
}

test("issues never carry review threads or review requests", () => {
  const items = classifyTarget(
    issue({ comments: [comment("c1", "alice")] }),
    ME,
    config,
  );
  assert.equal(items.length, 1);
  assert.equal(items[0]?.kind, "conversation");
});

test("CI reports one aggregated item naming only what failed", () => {
  const failing = pr({
    ciState: "FAILURE",
    failingChecks: ["lint", "typecheck"],
  });
  const { item } = applyCiTransition(failing, undefined, ME, config);
  assert.equal(item?.kind, "ci");
  assert.match(item?.summary ?? "", /lint, typecheck/);
  assert.deepEqual(item?.context?.failingChecks, ["lint", "typecheck"]);
});

test("a non-definitive rollup is not a red alert", () => {
  for (const state of ["PENDING", "NEUTRAL", "EXPECTED", "UNKNOWN"] as const) {
    const { item } = applyCiTransition(
      pr({ ciState: state }),
      undefined,
      ME,
      config,
    );
    assert.equal(item, null, `${state} must not alert`);
  }
});

test("a steady red CI does not re-alert on the next poll", () => {
  const failing = pr({ ciState: "FAILURE", failingChecks: ["lint"] });
  const first = applyCiTransition(failing, undefined, ME, config);
  const second = applyCiTransition(failing, first.memory, ME, config);
  assert.equal(first.newlyRed, true);
  assert.equal(second.newlyRed, false);
  assert.equal(first.item?.id, second.item?.id);
});

test("a new head commit re-alerts with a fresh id", () => {
  const first = applyCiTransition(
    pr({ ciState: "FAILURE", failingChecks: ["lint"] }),
    undefined,
    ME,
    config,
  );
  const second = applyCiTransition(
    pr({ ciState: "FAILURE", failingChecks: ["lint"], headSha: "sha-2" }),
    first.memory,
    ME,
    config,
  );
  assert.equal(second.newlyRed, true);
  assert.notEqual(first.item?.id, second.item?.id);
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
      prsRequested: { nodes: [] },
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
      prsRequested: { nodes: [] },
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
