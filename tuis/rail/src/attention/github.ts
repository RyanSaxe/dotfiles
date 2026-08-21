import { execFile } from "node:child_process";
import { promisify } from "node:util";

import type {
  ActorKind,
  CiState,
  GitHubActor,
  GitHubComment,
  GitHubSnapshot,
  GitHubTarget,
  IssueTarget,
  PullRequestTarget,
  RateLimit,
  ReviewThread,
} from "./types.js";

const execFileAsync = promisify(execFile);

const GRAPHQL_QUERY = /* GraphQL */ `
  fragment CommentFields on IssueComment {
    id
    author {
      login
      __typename
    }
    body
    createdAt
    url
    reactionGroups {
      viewerHasReacted
    }
  }

  fragment IssueFields on Issue {
    number
    title
    body
    url
    createdAt
    updatedAt
    author {
      login
      __typename
    }
    repository {
      nameWithOwner
    }
    labels(first: 5) {
      nodes {
        name
      }
    }
    comments(last: 100) {
      nodes {
        ...CommentFields
      }
    }
  }

  fragment PullRequestFields on PullRequest {
    number
    title
    body
    url
    createdAt
    updatedAt
    isDraft
    additions
    deletions
    changedFiles
    headRefOid
    author {
      login
      __typename
    }
    repository {
      nameWithOwner
    }
    reviewThreads(last: 50) {
      nodes {
        id
        isResolved
        comments(last: 20) {
          nodes {
            id
            author {
              login
              __typename
            }
            body
            createdAt
            url
            reactionGroups {
              viewerHasReacted
            }
          }
        }
      }
    }
    comments(last: 100) {
      nodes {
        ...CommentFields
      }
    }
    statusCheckRollup {
      state
      contexts(last: 100) {
        nodes {
          __typename
          ... on CheckRun {
            name
            conclusion
          }
          ... on StatusContext {
            context
            state
          }
        }
      }
    }
  }

  query {
    viewer {
      login
    }
    rateLimit {
      cost
      remaining
      resetAt
    }
    prsInvolved: search(
      query: "is:open is:pr involves:@me"
      type: ISSUE
      first: 100
    ) {
      nodes {
        ... on PullRequest {
          ...PullRequestFields
        }
      }
    }
    prsRequested: search(
      query: "is:open is:pr review-requested:@me"
      type: ISSUE
      first: 100
    ) {
      nodes {
        ... on PullRequest {
          ...PullRequestFields
        }
      }
    }
    issuesInvolved: search(
      query: "is:open is:issue involves:@me"
      type: ISSUE
      first: 100
    ) {
      nodes {
        ... on Issue {
          ...IssueFields
        }
      }
    }
  }
`;

interface RawActor {
  login?: string | null;
  __typename?: string | null;
}

interface RawReactionGroup {
  viewerHasReacted?: boolean | null;
}

interface RawComment {
  id?: string | null;
  author?: RawActor | null;
  body?: string | null;
  createdAt?: string | null;
  url?: string | null;
  reactionGroups?: RawReactionGroup[] | null;
}

interface RawThread {
  id?: string | null;
  isResolved?: boolean | null;
  comments?: { nodes?: Array<RawComment | null> | null } | null;
}

interface RawCheckContext {
  __typename?: string | null;
  name?: string | null;
  conclusion?: string | null;
  context?: string | null;
  state?: string | null;
}

interface RawIssue {
  number?: number | null;
  title?: string | null;
  body?: string | null;
  url?: string | null;
  createdAt?: string | null;
  updatedAt?: string | null;
  author?: RawActor | null;
  repository?: { nameWithOwner?: string | null } | null;
  labels?: { nodes?: Array<{ name?: string | null } | null> | null } | null;
  comments?: { nodes?: Array<RawComment | null> | null } | null;
}

interface RawPullRequest {
  isDraft?: boolean | null;
  createdAt?: string | null;
  additions?: number | null;
  deletions?: number | null;
  changedFiles?: number | null;
  number?: number | null;
  title?: string | null;
  body?: string | null;
  url?: string | null;
  updatedAt?: string | null;
  headRefOid?: string | null;
  author?: RawActor | null;
  repository?: { nameWithOwner?: string | null } | null;
  reviewThreads?: { nodes?: Array<RawThread | null> | null } | null;
  comments?: { nodes?: Array<RawComment | null> | null } | null;
  statusCheckRollup?: {
    state?: string | null;
    contexts?: { nodes?: Array<RawCheckContext | null> | null } | null;
  } | null;
}

interface RawSearch<T> {
  nodes?: Array<T | null> | null;
}

interface RawGraphqlData {
  viewer?: { login?: string | null } | null;
  rateLimit?: {
    cost?: number | null;
    remaining?: number | null;
    resetAt?: string | null;
  } | null;
  prsInvolved?: RawSearch<RawPullRequest> | null;
  prsRequested?: RawSearch<RawPullRequest> | null;
  issuesInvolved?: RawSearch<RawIssue> | null;
}

interface RawGraphqlResponse {
  data?: RawGraphqlData | null;
  errors?: Array<{ message?: string | null }> | null;
}

export interface GraphqlRunner {
  (): Promise<string>;
}

function actorKind(typeName: string | null | undefined): ActorKind {
  switch (typeName) {
    case "User":
      return "user";
    case "Bot":
      return "bot";
    case "App":
      return "app";
    default:
      return "unknown";
  }
}

function parseActor(actor: RawActor | null | undefined): GitHubActor | null {
  if (
    actor?.login === undefined ||
    actor.login === null ||
    actor.login === ""
  ) {
    return null;
  }
  return { login: actor.login, kind: actorKind(actor.__typename) };
}

function parseComment(comment: RawComment | null): GitHubComment | null {
  if (
    comment === null ||
    comment.id === undefined ||
    comment.id === null ||
    comment.createdAt === undefined ||
    comment.createdAt === null
  ) {
    return null;
  }
  return {
    id: comment.id,
    author: parseActor(comment.author),
    body: comment.body ?? "",
    createdAt: comment.createdAt,
    url: comment.url ?? "",
    viewerHasReacted:
      comment.reactionGroups?.some(
        (group) => group.viewerHasReacted === true,
      ) ?? false,
  };
}

function parseThread(thread: RawThread | null): ReviewThread | null {
  if (thread === null || thread.id === undefined || thread.id === null) {
    return null;
  }
  const rawComments = thread.comments?.nodes ?? [];
  return {
    id: thread.id,
    isResolved: thread.isResolved === true,
    comments: rawComments
      .map(parseComment)
      .filter((comment): comment is GitHubComment => comment !== null),
  };
}

function ciState(state: string | null | undefined): CiState {
  switch (state) {
    case "SUCCESS":
    case "FAILURE":
    case "ERROR":
    case "PENDING":
    case "EXPECTED":
    case "NEUTRAL":
      return state;
    default:
      return "UNKNOWN";
  }
}

// Only definitive failures. Cancelled, skipped, neutral, stale and pending
// are not failures — the locked rule is that non-definitive states never
// become a red alert, and naming them would make the preview lie.
const FAILED_CONCLUSIONS = new Set([
  "FAILURE",
  "TIMED_OUT",
  "ACTION_REQUIRED",
  "STARTUP_FAILURE",
]);
const FAILED_STATUS_STATES = new Set(["ERROR", "FAILURE"]);

function failingChecks(rollup: RawPullRequest["statusCheckRollup"]): string[] {
  const names: string[] = [];
  for (const context of rollup?.contexts?.nodes ?? []) {
    if (context === null || context === undefined) continue;
    if (context.__typename === "CheckRun") {
      if (FAILED_CONCLUSIONS.has(context.conclusion ?? "")) {
        names.push(context.name ?? "check");
      }
      continue;
    }
    if (FAILED_STATUS_STATES.has(context.state ?? "")) {
      names.push(context.context ?? "status");
    }
  }
  return [...new Set(names)];
}

function parseIssue(raw: RawIssue, source: string): IssueTarget | null {
  const repository = raw.repository?.nameWithOwner;
  const number = raw.number;
  if (
    repository === undefined ||
    repository === null ||
    number === undefined ||
    number === null
  ) {
    return null;
  }
  return {
    kind: "issue",
    repository,
    number,
    title: raw.title ?? `Issue #${number}`,
    body: raw.body ?? "",
    url: raw.url ?? `https://github.com/${repository}/issues/${number}`,
    createdAt: raw.createdAt ?? new Date(0).toISOString(),
    updatedAt: raw.updatedAt ?? new Date(0).toISOString(),
    author: parseActor(raw.author),
    labels: (raw.labels?.nodes ?? [])
      .map((label) => label?.name ?? "")
      .filter((name) => name !== ""),
    searchSources: [source],
    comments: (raw.comments?.nodes ?? [])
      .map(parseComment)
      .filter((comment): comment is GitHubComment => comment !== null),
  };
}

function parsePullRequest(
  raw: RawPullRequest,
  source: string,
): PullRequestTarget | null {
  const repository = raw.repository?.nameWithOwner;
  const number = raw.number;
  if (
    repository === undefined ||
    repository === null ||
    number === undefined ||
    number === null
  ) {
    return null;
  }
  const comments = (raw.comments?.nodes ?? [])
    .map(parseComment)
    .filter((comment): comment is GitHubComment => comment !== null);
  const reviewThreads = (raw.reviewThreads?.nodes ?? [])
    .map(parseThread)
    .filter((thread): thread is ReviewThread => thread !== null);
  return {
    kind: "pull_request",
    repository,
    number,
    title: raw.title ?? `PR #${number}`,
    body: raw.body ?? "",
    url: raw.url ?? `https://github.com/${repository}/pull/${number}`,
    createdAt: raw.createdAt ?? new Date(0).toISOString(),
    updatedAt: raw.updatedAt ?? new Date(0).toISOString(),
    isDraft: raw.isDraft === true,
    additions: raw.additions ?? 0,
    deletions: raw.deletions ?? 0,
    changedFiles: raw.changedFiles ?? 0,
    headSha: raw.headRefOid ?? "",
    author: parseActor(raw.author),
    ciState: ciState(raw.statusCheckRollup?.state),
    failingChecks: failingChecks(raw.statusCheckRollup),
    searchSources: [source],
    reviewRequested: source === "requested",
    reviewRequestFingerprint: source === "requested" ? "viewer" : "",
    comments,
    reviewThreads,
  };
}

// One target can arrive from several searches; merge rather than duplicate,
// keeping the review-request flag whichever search carried it.
function mergeTargets(
  pullRequests: Array<{
    source: string;
    search: RawSearch<RawPullRequest> | null | undefined;
  }>,
  issues: Array<{
    source: string;
    search: RawSearch<RawIssue> | null | undefined;
  }>,
): GitHubTarget[] {
  const merged = new Map<string, GitHubTarget>();
  const key = (target: GitHubTarget): string =>
    `${target.kind}:${target.repository}#${target.number}`;

  for (const entry of pullRequests) {
    for (const raw of entry.search?.nodes ?? []) {
      if (raw === null || raw === undefined) continue;
      const parsed = parsePullRequest(raw, entry.source);
      if (parsed === null) continue;
      const previous = merged.get(key(parsed));
      if (previous === undefined || previous.kind !== "pull_request") {
        merged.set(key(parsed), parsed);
        continue;
      }
      previous.searchSources = [
        ...new Set([...previous.searchSources, entry.source]),
      ];
      previous.reviewRequested ||= parsed.reviewRequested;
      if (
        previous.reviewRequestFingerprint === "" &&
        parsed.reviewRequestFingerprint !== ""
      ) {
        previous.reviewRequestFingerprint = parsed.reviewRequestFingerprint;
      }
    }
  }

  for (const entry of issues) {
    for (const raw of entry.search?.nodes ?? []) {
      if (raw === null || raw === undefined) continue;
      const parsed = parseIssue(raw, entry.source);
      if (parsed === null) continue;
      const previous = merged.get(key(parsed));
      if (previous === undefined) {
        merged.set(key(parsed), parsed);
        continue;
      }
      previous.searchSources = [
        ...new Set([...previous.searchSources, entry.source]),
      ];
    }
  }

  return [...merged.values()];
}

function parseRateLimit(raw: RawGraphqlData["rateLimit"]): RateLimit | null {
  if (
    raw === null ||
    raw === undefined ||
    raw.cost === undefined ||
    raw.cost === null ||
    raw.remaining === undefined ||
    raw.remaining === null ||
    raw.resetAt === undefined ||
    raw.resetAt === null
  ) {
    return null;
  }
  return { cost: raw.cost, remaining: raw.remaining, resetAt: raw.resetAt };
}

export function parseGithubResponse(
  stdout: string,
  requestDurationMs: number,
  fetchedAt = new Date().toISOString(),
): GitHubSnapshot {
  const response = JSON.parse(stdout) as RawGraphqlResponse;
  const errors =
    response.errors?.map((error) => error.message ?? "unknown GraphQL error") ??
    [];
  if (errors.length > 0) {
    throw new Error(`GitHub GraphQL: ${errors.join("; ")}`);
  }
  const data = response.data;
  if (data === null || data === undefined) {
    throw new Error("GitHub GraphQL: response data was missing");
  }
  const username = data?.viewer?.login;
  if (username === undefined || username === null || username === "") {
    throw new Error("GitHub GraphQL: viewer login was missing");
  }
  return {
    username,
    fetchedAt,
    requestDurationMs,
    rateLimit: parseRateLimit(data.rateLimit),
    targets: mergeTargets(
      [
        { source: "involved", search: data.prsInvolved },
        { source: "requested", search: data.prsRequested },
      ],
      [{ source: "involved", search: data.issuesInvolved }],
    ),
  };
}

async function runGhGraphql(): Promise<string> {
  try {
    const result = await execFileAsync(
      "gh",
      ["api", "graphql", "--field", `query=${GRAPHQL_QUERY}`],
      { maxBuffer: 16 * 1024 * 1024, timeout: 60_000 },
    );
    return result.stdout;
  } catch (error) {
    if (
      error instanceof Error &&
      "stderr" in error &&
      typeof error.stderr === "string" &&
      error.stderr.trim() !== ""
    ) {
      throw new Error(`gh api graphql: ${error.stderr.trim()}`);
    }
    throw error;
  }
}

export async function fetchGithubSnapshot(
  runQuery: GraphqlRunner = runGhGraphql,
): Promise<GitHubSnapshot> {
  const started = performance.now();
  const stdout = await runQuery();
  return parseGithubResponse(stdout, Math.round(performance.now() - started));
}

export function graphqlQueryForTests(): string {
  return GRAPHQL_QUERY;
}
