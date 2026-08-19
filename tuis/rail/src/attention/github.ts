import { execFile } from "node:child_process";
import { promisify } from "node:util";

import type {
  ActorKind,
  CiState,
  GitHubActor,
  GitHubComment,
  GitHubSnapshot,
  PullRequestSnapshot,
  RateLimit,
  ReviewThread,
} from "./types.js";

const execFileAsync = promisify(execFile);

const GRAPHQL_QUERY = /* GraphQL */ `
  fragment PullRequestFields on PullRequest {
    number
    title
    url
    updatedAt
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
    statusCheckRollup {
      state
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
    involved: search(
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
    requested: search(
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

interface RawPullRequest {
  number?: number | null;
  title?: string | null;
  url?: string | null;
  updatedAt?: string | null;
  headRefOid?: string | null;
  author?: RawActor | null;
  repository?: { nameWithOwner?: string | null } | null;
  reviewThreads?: { nodes?: Array<RawThread | null> | null } | null;
  comments?: { nodes?: Array<RawComment | null> | null } | null;
  statusCheckRollup?: { state?: string | null } | null;
}

interface RawSearch {
  nodes?: Array<RawPullRequest | null> | null;
}

interface RawGraphqlData {
  viewer?: { login?: string | null } | null;
  rateLimit?: {
    cost?: number | null;
    remaining?: number | null;
    resetAt?: string | null;
  } | null;
  involved?: RawSearch | null;
  requested?: RawSearch | null;
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

function parsePullRequest(
  raw: RawPullRequest,
  source: string,
): PullRequestSnapshot | null {
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
    repository,
    number,
    title: raw.title ?? `PR #${number}`,
    url: raw.url ?? `https://github.com/${repository}/pull/${number}`,
    updatedAt: raw.updatedAt ?? new Date(0).toISOString(),
    headSha: raw.headRefOid ?? "",
    author: parseActor(raw.author),
    ciState: ciState(raw.statusCheckRollup?.state),
    searchSources: [source],
    reviewRequested: source === "requested",
    reviewRequestFingerprint: source === "requested" ? "viewer" : "",
    comments,
    reviewThreads,
  };
}

function mergePullRequests(
  entries: Array<{ source: string; search: RawSearch | null | undefined }>,
): PullRequestSnapshot[] {
  const merged = new Map<string, PullRequestSnapshot>();
  for (const entry of entries) {
    for (const raw of entry.search?.nodes ?? []) {
      if (raw === null) continue;
      const parsed = parsePullRequest(raw, entry.source);
      if (parsed === null) continue;
      const key = `${parsed.repository}#${parsed.number}`;
      const previous = merged.get(key);
      if (previous === undefined) {
        merged.set(key, parsed);
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
    pullRequests: mergePullRequests([
      { source: "involved", search: data.involved },
      { source: "requested", search: data.requested },
    ]),
  };
}

async function runGhGraphql(): Promise<string> {
  const result = await execFileAsync(
    "gh",
    ["api", "graphql", "--field", `query=${GRAPHQL_QUERY}`],
    { maxBuffer: 16 * 1024 * 1024 },
  );
  return result.stdout;
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
