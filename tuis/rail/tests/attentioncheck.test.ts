import assert from "node:assert/strict";

import {
  defaultAttentionConfig,
  validateAttentionConfig,
} from "../src/attention/config.js";
import { applyCiTransition } from "../src/attention/ci.js";
import { classifyTarget } from "../src/attention/classify.js";
import { parseGithubResponse } from "../src/attention/github.js";
import {
  acknowledgeItem,
  emptyObserverState,
  markNotified,
  reconcileAttention,
  retryAfterForRateLimit,
} from "../src/attention/state.js";
import type {
  GitHubActor,
  GitHubComment,
  PullRequestTarget,
} from "../src/attention/types.js";

const human = (login: string): GitHubActor => ({ login, kind: "user" });
const bot = (login: string): GitHubActor => ({ login, kind: "bot" });

const comment = (
  id: string,
  author: GitHubActor,
  body: string,
  createdAt: string,
  viewerHasReacted = false,
): GitHubComment => ({
  id,
  author,
  body,
  createdAt,
  url: `https://github.com/example/repo/pull/7#${id}`,
  viewerHasReacted,
});

const pr = (overrides: Partial<PullRequestTarget> = {}): PullRequestTarget => ({
  repository: "example/repo",
  number: 7,
  title: "Improve observer",
  body: "Review the observer changes.",
  url: "https://github.com/example/repo/pull/7",
  updatedAt: "2026-08-19T16:00:00Z",
  headSha: "head-1",
  author: human("ryansaxe"),
  kind: "pull_request",
  isDraft: false,
  additions: 0,
  deletions: 0,
  changedFiles: 0,
  createdAt: "2026-08-19T10:00:00Z",
  ciState: "SUCCESS",
  failingChecks: [],
  searchSources: ["involved"],
  reviewRequested: false,
  reviewRequestFingerprint: "",
  comments: [],
  reviewThreads: [],
  ...overrides,
});

const config = defaultAttentionConfig();

const humanThread = pr({
  author: human("someone-else"),
  reviewThreads: [
    {
      id: "thread-1",
      isResolved: false,
      comments: [
        comment(
          "c1",
          human("ryansaxe"),
          "I will check this.",
          "2026-08-19T15:00:00Z",
        ),
        comment(
          "c2",
          human("reviewer"),
          "Please fix this.",
          "2026-08-19T16:01:00Z",
        ),
      ],
    },
  ],
});
assert.equal(classifyTarget(humanThread, "ryansaxe", config).length, 1);
assert.equal(
  classifyTarget(humanThread, "ryansaxe", config)[0]?.kind,
  "review_comment",
);

const botThread = pr({
  reviewThreads: [
    {
      id: "thread-bot",
      isResolved: false,
      comments: [
        comment(
          "bot-1",
          bot("codecov"),
          "Coverage is 81%.",
          "2026-08-19T16:01:00Z",
        ),
      ],
    },
  ],
});
assert.equal(classifyTarget(botThread, "ryansaxe", config).length, 0);

const allowConfig = validateAttentionConfig(
  { actors: { allow: ["claude-reviewer"], ignore: [] }, own_pr_ci: true },
  "fixture",
);
const allowedBot = pr({
  reviewThreads: [
    {
      id: "thread-allowed",
      isResolved: false,
      comments: [
        comment(
          "bot-2",
          bot("claude-reviewer"),
          "Consider this change.",
          "2026-08-19T16:02:00Z",
        ),
      ],
    },
  ],
});
assert.equal(classifyTarget(allowedBot, "ryansaxe", allowConfig).length, 1);
assert.throws(
  () =>
    validateAttentionConfig(
      { actors: { allow: ["bot"], ignore: ["BOT"] } },
      "fixture",
    ),
  /cannot be both allowed and ignored/,
);

const mentioned = pr({
  author: human("someone-else"),
  comments: [
    comment(
      "mention",
      human("reviewer"),
      "@ryansaxe please take a look",
      "2026-08-19T16:03:00Z",
    ),
  ],
});
assert.equal(classifyTarget(mentioned, "ryansaxe", config).length, 1);

const reacted = pr({
  reviewThreads: [
    {
      id: "thread-reacted",
      isResolved: false,
      comments: [
        comment(
          "reacted",
          human("reviewer"),
          "Acknowledged?",
          "2026-08-19T16:04:00Z",
          true,
        ),
      ],
    },
  ],
});
assert.equal(classifyTarget(reacted, "ryansaxe", config).length, 0);

const ciPr = pr({ ciState: "FAILURE", headSha: "head-1" });
const firstCi = applyCiTransition(ciPr, undefined, "ryansaxe", config);
assert.ok(firstCi.item);
assert.equal(firstCi.memory.redEpoch, 1);
const repeatedCi = applyCiTransition(ciPr, firstCi.memory, "ryansaxe", config);
assert.equal(repeatedCi.item?.id, firstCi.item?.id);
assert.equal(repeatedCi.newlyRed, false);
const recoveredCi = applyCiTransition(
  { ...ciPr, ciState: "SUCCESS" },
  repeatedCi.memory,
  "ryansaxe",
  config,
);
assert.equal(recoveredCi.item, null);
const redAgain = applyCiTransition(
  ciPr,
  recoveredCi.memory,
  "ryansaxe",
  config,
);
assert.ok(redAgain.item);
assert.equal(redAgain.memory.redEpoch, 2);

const rateReset = "2026-08-19T17:00:00.000Z";
assert.equal(
  retryAfterForRateLimit(
    { cost: 5, remaining: 99, resetAt: rateReset },
    Date.parse("2026-08-19T16:00:00.000Z"),
  ),
  rateReset,
);
assert.equal(
  retryAfterForRateLimit(
    { cost: 5, remaining: 101, resetAt: rateReset },
    Date.parse("2026-08-19T16:00:00.000Z"),
  ),
  null,
);

const parsed = parseGithubResponse(
  JSON.stringify({
    data: {
      viewer: { login: "ryansaxe" },
      rateLimit: {
        cost: 42,
        remaining: 4990,
        resetAt: "2026-08-19T17:00:00Z",
      },
      prsInvolved: {
        nodes: [
          {
            number: 7,
            title: "Improve observer",
            body: "Review the observer changes.",
            url: "https://github.com/example/repo/pull/7",
            updatedAt: "2026-08-19T16:00:00Z",
            headRefOid: "head-1",
            author: { login: "ryansaxe", __typename: "User" },
            repository: { nameWithOwner: "example/repo" },
            reviewThreads: { nodes: [] },
            comments: { nodes: [] },
            statusCheckRollup: { state: "SUCCESS" },
          },
        ],
      },
      prsRequested: {
        nodes: [
          {
            number: 7,
            title: "Improve observer",
            body: "Review the observer changes.",
            url: "https://github.com/example/repo/pull/7",
            updatedAt: "2026-08-19T16:00:00Z",
            headRefOid: "head-1",
            author: { login: "ryansaxe", __typename: "User" },
            repository: { nameWithOwner: "example/repo" },
            reviewThreads: { nodes: [] },
            comments: { nodes: [] },
            statusCheckRollup: { state: "SUCCESS" },
          },
        ],
      },
    },
  }),
  21,
);
assert.equal(parsed.targets.length, 1);
assert.deepEqual(parsed.targets[0]?.searchSources.sort(), [
  "involved",
  "requested",
]);
const first = parsed.targets[0];
assert.equal(first?.kind, "pull_request");
assert.equal(
  first?.kind === "pull_request" ? first.reviewRequested : null,
  true,
);
assert.equal(parsed.targets[0]?.body, "Review the observer changes.");

const reviewItem = classifyTarget(mentioned, "ryansaxe", config)[0];
assert.ok(reviewItem);
const reconciled = reconcileAttention(emptyObserverState(), [reviewItem], {});
assert.equal(reconciled.pendingNotifications.length, 1);
const acknowledged = markNotified(
  { ...reconciled.state, lastSuccessfulSyncAt: "2026-08-19T16:05:00Z" },
  [reviewItem.id],
);
const repeated = reconcileAttention(acknowledged, [reviewItem], {});
assert.equal(repeated.pendingNotifications.length, 0);

const checked = acknowledgeItem(reconciled.state, reviewItem.id);
const checkedAgain = reconcileAttention(checked, [reviewItem], {});
assert.equal(checkedAgain.pendingNotifications.length, 0);

const newEvent = classifyTarget(
  {
    ...mentioned,
    comments: [
      ...mentioned.comments,
      comment(
        "mention-new",
        human("reviewer"),
        "@ryansaxe one more thing",
        "2026-08-19T16:06:00Z",
      ),
    ],
  },
  "ryansaxe",
  config,
)[0];
assert.ok(newEvent);
assert.notEqual(newEvent.id, reviewItem.id);
const resurfaced = reconcileAttention(checkedAgain.state, [newEvent], {});
assert.equal(resurfaced.pendingNotifications.length, 1);

console.log("attention checks passed");
