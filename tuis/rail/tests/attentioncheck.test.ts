// Exercises the account-wide attention contract without contacting GitHub.

import assert from "node:assert/strict";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { applyCiTransition } from "../src/attention/ci.js";
import { attentionItem, classifyTarget } from "../src/attention/classify.js";
import {
  defaultAttentionConfig,
  validateAttentionConfig,
} from "../src/attention/config.js";
import { parseGithubResponse } from "../src/attention/github.js";
import {
  acknowledgeItem,
  emptyObserverState,
  loadObserverState,
  reconcileAttention,
  retryAfterForRateLimit,
  unacknowledgedItems,
} from "../src/attention/state.js";
import type {
  GitHubActor,
  GitHubComment,
  PullRequestTarget,
} from "../src/attention/types.js";

const ME = "ryansaxe";
const BASELINE = "2026-08-19T16:00:00.000Z";

const oldStateDirectory = await mkdtemp(join(tmpdir(), "rail-attention-"));
const oldStatePath = join(oldStateDirectory, "state.json");
await writeFile(
  oldStatePath,
  JSON.stringify({ version: 1, items: { "old-comment": {} } }),
);
const cleanState = await loadObserverState(oldStatePath);
assert.equal(cleanState.version, 2);
assert.deepEqual(cleanState.items, {});
assert.equal(cleanState.baselineAt, null);
await rm(oldStateDirectory, { recursive: true, force: true });

const user = (login: string): GitHubActor => ({ login, kind: "user" });
const bot = (login: string): GitHubActor => ({ login, kind: "bot" });

const comment = (
  id: string,
  author: GitHubActor,
  createdAt: string,
  viewerHasReacted = false,
): GitHubComment => ({
  id,
  author,
  body: `comment ${id}`,
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
  createdAt: "2026-08-19T10:00:00.000Z",
  updatedAt: "2026-08-19T17:00:00.000Z",
  headSha: "head-1",
  author: user(ME),
  kind: "pull_request",
  isDraft: false,
  additions: 0,
  deletions: 0,
  changedFiles: 0,
  ciState: "SUCCESS",
  failingChecks: [],
  searchSources: ["involved"],
  comments: [],
  reviewThreads: [],
  ...overrides,
});

const config = defaultAttentionConfig();

const externalComment = comment(
  "external",
  user("alice"),
  "2026-08-19T16:01:00.000Z",
);
const commented = pr({
  author: user(ME),
  comments: [externalComment],
});
const firstItem = classifyTarget(commented, ME, config, {
  baselineAt: BASELINE,
});
assert.equal(firstItem?.id, "pull_request:example/repo#7");
assert.deepEqual(
  firstItem?.reasons.map((reason) => reason.kind),
  ["comment"],
);

const acknowledged = acknowledgeItem(
  reconcileAttention(emptyObserverState(), [firstItem!], {}),
  firstItem!.id,
);
assert.deepEqual(unacknowledgedItems(acknowledged), []);

const laterComment = comment(
  "later",
  user("alice"),
  "2026-08-19T17:01:00.000Z",
);
const laterItem = classifyTarget(
  { ...commented, comments: [externalComment, laterComment] },
  ME,
  config,
  { baselineAt: BASELINE },
);
assert.equal(laterItem?.id, firstItem?.id);
assert.notEqual(laterItem?.activityKey, firstItem?.activityKey);
assert.equal(
  unacknowledgedItems(reconcileAttention(acknowledged, [laterItem!], {}))
    .length,
  1,
);

const replied = classifyTarget(
  {
    ...commented,
    comments: [
      externalComment,
      comment("reply", user(ME), "2026-08-19T16:02:00.000Z"),
    ],
  },
  ME,
  config,
  { baselineAt: BASELINE },
);
assert.equal(replied, null);

const reacted = classifyTarget(
  {
    ...commented,
    comments: [{ ...externalComment, viewerHasReacted: true }],
  },
  ME,
  config,
  { baselineAt: BASELINE },
);
assert.equal(reacted, null);

const botComment = classifyTarget(
  {
    ...commented,
    comments: [comment("bot", bot("ci-bot"), externalComment.createdAt)],
  },
  ME,
  config,
  { baselineAt: BASELINE },
);
assert.equal(botComment, null);

const allowedBotConfig = validateAttentionConfig(
  { actors: { allow: ["ci-bot"], ignore: [] }, own_pr_ci: true },
  "fixture",
);
assert.equal(
  classifyTarget(
    {
      ...commented,
      comments: [comment("bot", bot("ci-bot"), externalComment.createdAt)],
    },
    ME,
    allowedBotConfig,
    { baselineAt: BASELINE },
  )?.reasons[0]?.actor?.login,
  "ci-bot",
);
assert.throws(
  () =>
    validateAttentionConfig(
      { actors: { allow: ["bot"], ignore: ["BOT"] } },
      "fixture",
    ),
  /cannot be both allowed and ignored/,
);

const ciPr = pr({ ciState: "FAILURE", failingChecks: ["lint"] });
const firstCi = applyCiTransition(ciPr, undefined, ME, config, BASELINE);
assert.equal(firstCi.reason?.kind, "ci");
assert.equal(firstCi.memory.redEpoch, 1);
const combined = attentionItem(ciPr, [firstItem!.reasons[0]!, firstCi.reason!]);
assert.equal(combined.id, "pull_request:example/repo#7");
assert.equal(combined.reasons.length, 2);
const acknowledgedCombined = acknowledgeItem(
  reconcileAttention(emptyObserverState(), [combined], {}),
  combined.id,
);
const ciOnly = attentionItem(ciPr, [firstCi.reason!]);
assert.deepEqual(
  unacknowledgedItems(reconcileAttention(acknowledgedCombined, [ciOnly], {})),
  [],
);
const repeatedCi = applyCiTransition(
  ciPr,
  firstCi.memory,
  ME,
  config,
  BASELINE,
);
assert.equal(repeatedCi.reason?.id, firstCi.reason?.id);
assert.equal(repeatedCi.newlyRed, false);
const recoveredCi = applyCiTransition(
  { ...ciPr, ciState: "SUCCESS" },
  repeatedCi.memory,
  ME,
  config,
  BASELINE,
);
assert.equal(recoveredCi.reason, null);
const redAgain = applyCiTransition(
  ciPr,
  recoveredCi.memory,
  ME,
  config,
  BASELINE,
);
assert.equal(redAgain.memory.redEpoch, 2);
assert.equal(redAgain.reason?.kind, "ci");

const historicalCi = applyCiTransition(
  { ...ciPr, updatedAt: "2026-08-19T15:59:00.000Z" },
  undefined,
  ME,
  config,
  BASELINE,
);
assert.equal(historicalCi.reason, null);
assert.equal(historicalCi.memory.alerted, false);

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
      viewer: { login: ME },
      rateLimit: {
        cost: 42,
        remaining: 4990,
        resetAt: rateReset,
      },
      prsInvolved: {
        nodes: [
          {
            number: 7,
            title: "Improve observer",
            body: "Review the observer changes.",
            url: "https://github.com/example/repo/pull/7",
            updatedAt: "2026-08-19T17:00:00.000Z",
            headRefOid: "head-1",
            author: { login: ME, __typename: "User" },
            repository: { nameWithOwner: "example/repo" },
            reviewThreads: { nodes: [] },
            comments: { nodes: [] },
            statusCheckRollup: { state: "SUCCESS" },
          },
        ],
        pageInfo: { hasNextPage: false, endCursor: null },
      },
    },
  }),
  21,
);
assert.equal(parsed.targets.length, 1);
assert.deepEqual(parsed.targets[0]?.searchSources, ["involved"]);
assert.ok(!JSON.stringify(parsed).includes("reviewRequested"));

console.log("attention checks passed");
