import assert from "node:assert/strict";
import { test } from "node:test";

import {
  fetchGithubSync,
  type GraphqlRunner,
} from "../src/attention/github.js";
import {
  commitGithubSync,
  emptyObserverState,
  FULL_RECONCILIATION_INTERVAL_MS,
  acknowledgeItem,
  reconcileAttention,
  reconcileGithubAttention,
  shouldRunFullReconciliation,
  unacknowledgedItems,
} from "../src/attention/state.js";
import type {
  AttentionItem,
  AttentionReason,
  GitHubActor,
} from "../src/attention/types.js";

const ME = "ryansaxe";
const START = "2026-08-29T10:05:00.000Z";
const CHECKPOINT = "2026-08-29T10:00:00.000Z";
const RATE_LIMIT = {
  cost: 1,
  remaining: 4999,
  resetAt: "2026-08-29T11:00:00.000Z",
};

const actor = (login: string): GitHubActor => ({ login, kind: "user" });

function graphqlResponse(data: Record<string, unknown>): string {
  return JSON.stringify({ data: { viewer: { login: ME }, ...data } });
}

function page<T>(
  nodes: T[],
  hasNextPage = false,
  endCursor: string | null = null,
) {
  return { nodes, pageInfo: { hasNextPage, endCursor } };
}

function discoveryNode(
  id: string,
  number: number,
  updatedAt: string,
  repository = "example/repo",
) {
  return {
    id,
    number,
    createdAt: "2026-08-29T08:00:00.000Z",
    updatedAt,
    repository: { nameWithOwner: repository },
  };
}

function rawComment(id: string, createdAt: string, login = "alice") {
  return {
    id,
    author: { login, __typename: "User" },
    body: `comment ${id}`,
    createdAt,
    url: `https://github.com/example/repo/pull/7#${id}`,
    reactionGroups: [{ viewerHasReacted: false }],
  };
}

function rawPullRequest(
  id: string,
  comments: ReturnType<typeof rawComment>[],
  reviewThreads: unknown[] = [],
  contexts: unknown[] = [],
  updatedAt = "2026-08-29T10:01:00.000Z",
  number = 7,
) {
  return {
    id,
    number,
    title: "A pull request",
    body: "body",
    url: "https://github.com/example/repo/pull/7",
    createdAt: "2026-08-29T08:00:00.000Z",
    updatedAt,
    isDraft: false,
    additions: 3,
    deletions: 1,
    changedFiles: 1,
    headRefOid: "head-1",
    author: { login: ME, __typename: "User" },
    repository: { nameWithOwner: "example/repo" },
    comments: page(comments),
    reviewThreads: page(reviewThreads),
    statusCheckRollup: {
      state: "SUCCESS",
      contexts: page(contexts),
    },
  };
}

function paginatedPullRequestRunner(): {
  runner: GraphqlRunner;
  queries: string[];
} {
  const queries: string[] = [];
  const runner: GraphqlRunner = async (query) => {
    queries.push(query);

    if (query.includes('node(id: "thread-1")')) {
      const secondPage = query.includes('after: "thread-comments-2"');
      return graphqlResponse({
        rateLimit: RATE_LIMIT,
        node: {
          id: "thread-1",
          isResolved: false,
          comments: page(
            [
              rawComment(
                secondPage ? "review-2" : "review-1",
                secondPage
                  ? "2026-08-29T10:04:00.000Z"
                  : "2026-08-29T10:03:00.000Z",
                secondPage ? "bob" : ME,
              ),
            ],
            !secondPage,
            secondPage ? null : "thread-comments-2",
          ),
        },
      });
    }

    if (query.includes('node(id: "pr-1")')) {
      const secondPage = query.includes('after: "comments-2"');
      const details = rawPullRequest(
        "pr-1",
        [
          rawComment(
            secondPage ? "comment-2" : "comment-1",
            secondPage
              ? "2026-08-29T10:02:00.000Z"
              : "2026-08-29T10:01:00.000Z",
          ),
        ],
        secondPage ? [] : [{ id: "thread-1", isResolved: false }],
        secondPage ? [] : [],
      );
      if (!secondPage) {
        details.comments = page(
          [rawComment("comment-1", "2026-08-29T10:01:00.000Z")],
          true,
          "comments-2",
        );
        details.reviewThreads = page([{ id: "thread-1", isResolved: false }]);
      }
      return graphqlResponse({ rateLimit: RATE_LIMIT, node: details });
    }

    if (query.includes("search(")) {
      const secondPage = query.includes('after: "discovery-2"');
      if (secondPage) {
        return graphqlResponse({
          rateLimit: RATE_LIMIT,
          prsInvolved: page([discoveryNode("pr-1", 7, START)], false),
        });
      }
      return graphqlResponse({
        rateLimit: RATE_LIMIT,
        prsInvolved: page(
          [discoveryNode("pr-1", 7, "2026-08-29T10:01:00.000Z")],
          true,
          "discovery-2",
        ),
        issuesInvolved: page([]),
      });
    }

    throw new Error(`unexpected query: ${query}`);
  };
  return { runner, queries };
}

test("full sync paginates discovery and nested detail connections, then deduplicates targets", async () => {
  const { runner, queries } = paginatedPullRequestRunner();
  const result = await fetchGithubSync(
    { fullReconciliation: true, startedAt: START },
    runner,
  );
  const target = result.snapshot.targets[0];

  assert.equal(result.fullReconciliation, true);
  assert.equal(result.processedThrough, START);
  assert.deepEqual(result.refreshedTargetKeys, ["pull_request:example/repo#7"]);
  assert.equal(result.snapshot.targets.length, 1);
  assert.deepEqual(target?.searchSources.sort(), ["involved"]);
  assert.equal(target?.kind, "pull_request");
  assert.equal(target?.comments.length, 2);
  assert.equal(
    target?.kind === "pull_request"
      ? target.reviewThreads[0]?.comments.length
      : null,
    2,
  );
  assert.ok(queries.some((query) => query.includes('after: "discovery-2"')));
  assert.equal(
    queries.filter((query) => query.includes('node(id: "pr-1")')).length,
    2,
  );
  assert.ok(queries.every((query) => !query.includes("comments(last:")));
});

test("incremental discovery uses a coarse date bound but details only targets past the precise checkpoint", async () => {
  const queries: string[] = [];
  let detailCalls = 0;
  const runner: GraphqlRunner = async (query) => {
    queries.push(query);
    if (query.includes("search(")) {
      return graphqlResponse({
        rateLimit: RATE_LIMIT,
        prsInvolved: page([
          discoveryNode("old", 1, "2026-08-29T08:59:00.000Z"),
          discoveryNode("new", 2, "2026-08-29T09:01:00.000Z"),
        ]),
        issuesInvolved: page([]),
      });
    }
    detailCalls += 1;
    assert.ok(query.includes('node(id: "new")'));
    return graphqlResponse({
      rateLimit: RATE_LIMIT,
      node: rawPullRequest("new", [], [], [], "2026-08-29T09:01:00.000Z", 2),
    });
  };

  const result = await fetchGithubSync(
    {
      since: CHECKPOINT,
      fullReconciliation: false,
      startedAt: START,
    },
    runner,
  );

  assert.equal(detailCalls, 1);
  assert.equal(result.snapshot.targets[0]?.number, 2);
  assert.ok(queries[0]?.includes("updated:>=2026-08-29"));
  assert.ok(!queries[0]?.includes("comments("));
});

test("a page failure does not advance a checkpoint, and retry starts from that checkpoint", async () => {
  const { runner: realRunner } = paginatedPullRequestRunner();
  let fail = true;
  const runner: GraphqlRunner = async (query) => {
    if (fail && query.includes('after: "discovery-2"')) {
      throw new Error("temporary page failure");
    }
    return realRunner(query);
  };
  const previous = {
    ...emptyObserverState(),
    githubSync: {
      processedThrough: CHECKPOINT,
      lastFullReconciliationAt: CHECKPOINT,
    },
  };

  await assert.rejects(
    fetchGithubSync(
      { since: CHECKPOINT, fullReconciliation: false, startedAt: START },
      runner,
    ),
    /temporary page failure/,
  );
  assert.equal(previous.githubSync?.processedThrough, CHECKPOINT);

  fail = false;
  const result = await fetchGithubSync(
    { since: CHECKPOINT, fullReconciliation: false, startedAt: START },
    runner,
  );
  const committed = commitGithubSync(
    previous,
    result.processedThrough,
    result.fullReconciliation,
  );
  assert.equal(committed.githubSync?.processedThrough, START);
  assert.equal(committed.githubSync?.lastFullReconciliationAt, CHECKPOINT);
});

test("a detail failure also leaves the previous checkpoint available for retry", async () => {
  const { runner: realRunner } = paginatedPullRequestRunner();
  let fail = true;
  const runner: GraphqlRunner = async (query) => {
    if (
      fail &&
      query.includes('node(id: "pr-1")') &&
      !query.includes("PullRequestReviewThread")
    ) {
      throw new Error("temporary detail failure");
    }
    return realRunner(query);
  };
  const previous = {
    ...emptyObserverState(),
    githubSync: {
      processedThrough: CHECKPOINT,
      lastFullReconciliationAt: CHECKPOINT,
    },
  };

  await assert.rejects(
    fetchGithubSync(
      { since: CHECKPOINT, fullReconciliation: false, startedAt: START },
      runner,
    ),
    /temporary detail failure/,
  );
  assert.equal(previous.githubSync?.processedThrough, CHECKPOINT);

  fail = false;
  const result = await fetchGithubSync(
    { since: CHECKPOINT, fullReconciliation: false, startedAt: START },
    runner,
  );
  assert.equal(result.processedThrough, START);
});

function attentionItem(
  id: string,
  repository: string,
  number: number,
  createdAt: string,
): AttentionItem {
  const reason: AttentionReason = {
    id: `comment:${createdAt}`,
    kind: "comment",
    summary: "A comment",
    actor: actor("alice"),
    createdAt,
    priority: "normal",
  };
  return {
    id,
    targetKind: "pull_request",
    repository,
    number,
    title: "Review",
    url: `https://github.com/${repository}/pull/${number}`,
    reasons: [reason],
    activityKey: reason.id,
  };
}

test("incremental reconciliation replaces only refreshed targets and keeps other acknowledgements", () => {
  const changed = attentionItem(
    "pull_request:example/repo#1",
    "example/repo",
    1,
    "2026-08-29T09:00:00.000Z",
  );
  const unchanged = attentionItem(
    "pull_request:other/repo#2",
    "other/repo",
    2,
    "2026-08-29T09:00:00.000Z",
  );
  const replacement = attentionItem(
    "pull_request:example/repo#1",
    "example/repo",
    1,
    "2026-08-29T10:01:00.000Z",
  );
  const previous = {
    ...emptyObserverState(),
    items: { [changed.id]: changed, [unchanged.id]: unchanged },
    acknowledged: { [unchanged.id]: unchanged.activityKey },
  };

  const result = reconcileGithubAttention(
    previous,
    [replacement],
    {},
    ["pull_request:example/repo#1"],
    false,
  );

  assert.deepEqual(
    Object.keys(result.items).sort(),
    [replacement.id, unchanged.id].sort(),
  );
  assert.equal(result.acknowledged[unchanged.id], unchanged.activityKey);
  assert.deepEqual(
    unacknowledgedItems(result).map((item) => item.id),
    [replacement.id],
  );
});

test("an acknowledgement hides one activity revision but a later event reopens the same target", () => {
  const old = attentionItem(
    "pull_request:example/repo#1",
    "example/repo",
    1,
    "2026-08-29T10:04:59.000Z",
  );
  const acknowledged = acknowledgeItem(
    reconcileAttention(emptyObserverState(), [old], {}),
    old.id,
  );
  assert.deepEqual(unacknowledgedItems(acknowledged), []);

  const fresh = attentionItem(
    "pull_request:example/repo#1",
    "example/repo",
    1,
    START,
  );
  const resurfaced = reconcileAttention(acknowledged, [fresh], {});
  assert.deepEqual(
    unacknowledgedItems(resurfaced).map((item) => item.id),
    [fresh.id],
  );
});

test("full reconciliation is periodic, while incremental commits keep the last full timestamp", () => {
  const first = commitGithubSync(emptyObserverState(), CHECKPOINT, true);
  const atBoundary = Date.parse(CHECKPOINT) + FULL_RECONCILIATION_INTERVAL_MS;
  assert.equal(shouldRunFullReconciliation(first, atBoundary - 1), false);
  assert.equal(shouldRunFullReconciliation(first, atBoundary), true);

  const next = commitGithubSync(first, START, false);
  assert.equal(next.githubSync?.processedThrough, START);
  assert.equal(next.githubSync?.lastFullReconciliationAt, CHECKPOINT);
});
