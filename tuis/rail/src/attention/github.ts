import { execFile } from "node:child_process";
import { promisify } from "node:util";

import type {
  ActorKind,
  CiState,
  GitHubActor,
  GitHubComment,
  GitHubReview,
  GitHubReviewState,
  GitHubSnapshot,
  GitHubTarget,
  IssueTarget,
  PullRequestTarget,
  RateLimit,
  ReviewThread,
} from "./types.js";

const execFileAsync = promisify(execFile);

// Keep each GraphQL request small. Discovery returns metadata only; detail
// requests fetch one target and one page of each connection at a time.
const DISCOVERY_PAGE_SIZE = 25;
const DETAIL_PAGE_SIZE = 25;

// GitHub's documented `updated` search qualifier accepts a date, not a full
// timestamp. The live path uses that date as a coarse server-side bound, then
// applies the precise checkpoint locally before fetching details.
export const SYNC_LOOKBACK_MS = 60 * 60 * 1000;

// GitHub ORs repeated `repo:` qualifiers. Twenty fit comfortably inside the
// query-length limit (verified: 575 characters, no error), so watch lists are
// chunked at that size rather than issuing one search per repository.
const WATCH_CHUNK = 20;

function chunk<T>(items: readonly T[], size: number): T[][] {
  const out: T[][] = [];
  for (let index = 0; index < items.length; index += size) {
    out.push(items.slice(index, index + size));
  }
  return out;
}

interface DiscoverySpec {
  alias: string;
  kind: "pull_request" | "issue";
  source: string;
  query: string;
}

interface DiscoveredTarget {
  id: string;
  kind: "pull_request" | "issue";
  repository: string;
  number: number;
  createdAt: string;
  updatedAt: string;
  searchSources: string[];
}

export interface GithubSyncOptions {
  watch?: readonly string[];
  since?: string | null;
  fullReconciliation?: boolean;
  startedAt?: string;
}

export interface GithubSyncResult {
  snapshot: GitHubSnapshot;
  refreshedTargetKeys: string[];
  fullReconciliation: boolean;
  processedThrough: string;
}

function graphqlString(value: string): string {
  return JSON.stringify(value);
}

function cursorArgument(cursor: string | null | undefined): string {
  return cursor === null || cursor === undefined
    ? "null"
    : graphqlString(cursor);
}

function checkpointDate(since: string): string {
  const timestamp = Date.parse(since);
  if (!Number.isFinite(timestamp)) {
    throw new Error(`GitHub sync checkpoint is not a date: ${since}`);
  }
  return new Date(timestamp).toISOString().slice(0, 10);
}

function discoverySpecs(
  watch: readonly string[],
  since: string | null,
): DiscoverySpec[] {
  const updated = since === null ? "" : ` updated:>=${checkpointDate(since)}`;
  const specs: DiscoverySpec[] = [
    {
      alias: "prsInvolved",
      kind: "pull_request",
      source: "involved",
      query: `is:open is:pr involves:@me sort:updated-desc${updated}`,
    },
    {
      alias: "issuesInvolved",
      kind: "issue",
      source: "involved",
      query: `is:open is:issue involves:@me sort:updated-desc${updated}`,
    },
  ];

  // Watching a repository covers both its pull requests and its issues, so
  // one list drives both searches.
  chunk(watch, WATCH_CHUNK).forEach((group, index) => {
    const qualifiers = group.map((repo) => `repo:${repo}`).join(" ");
    specs.push({
      alias: `watchedPrs${index}`,
      kind: "pull_request",
      source: "watched",
      query: `is:open is:pr -is:draft sort:updated-desc ${qualifiers}${updated}`,
    });
  });
  chunk(watch, WATCH_CHUNK).forEach((group, index) => {
    const qualifiers = group.map((repo) => `repo:${repo}`).join(" ");
    specs.push({
      alias: `watchedIssues${index}`,
      kind: "issue",
      source: "watched",
      query: `is:open is:issue sort:updated-desc ${qualifiers}${updated}`,
    });
  });
  return specs;
}

function discoveryNodeFields(kind: DiscoverySpec["kind"]): string {
  if (kind === "pull_request") {
    return `
          ... on PullRequest {
            id
            number
            createdAt
            updatedAt
            repository {
              nameWithOwner
            }
          }`;
  }
  return `
          ... on Issue {
            id
            number
            createdAt
            updatedAt
            repository {
              nameWithOwner
            }
          }`;
}

function buildDiscoveryQuery(
  specs: readonly DiscoverySpec[],
  cursors: ReadonlyMap<string, string | null>,
): string {
  const searches = specs
    .map(
      (spec) => `    ${spec.alias}: search(
      query: ${graphqlString(spec.query)}
      type: ISSUE
      first: ${DISCOVERY_PAGE_SIZE}
      after: ${cursorArgument(cursors.get(spec.alias))}
    ) {
      nodes {${discoveryNodeFields(spec.kind)}
      }
      pageInfo {
        endCursor
        hasNextPage
      }
    }`,
    )
    .join("\n");
  return `query {
    viewer {
      login
    }
    rateLimit {
      cost
      remaining
      resetAt
    }
${searches}
  }`;
}

// Kept as the small query builder used by the existing parser tests and by
// callers that only need a first discovery page. Live syncing supplies its
// cursors through the private builder above.
export function buildQuery(watch: readonly string[]): string {
  return buildDiscoveryQuery(discoverySpecs(watch, null), new Map());
}

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
  comments?: RawSearch<RawComment> | null;
}

interface RawReview {
  id?: string | null;
  author?: RawActor | null;
  body?: string | null;
  state?: string | null;
  submittedAt?: string | null;
  url?: string | null;
}

interface RawCheckContext {
  __typename?: string | null;
  name?: string | null;
  conclusion?: string | null;
  context?: string | null;
  state?: string | null;
}

interface RawIssue {
  id?: string | null;
  number?: number | null;
  title?: string | null;
  body?: string | null;
  url?: string | null;
  createdAt?: string | null;
  updatedAt?: string | null;
  author?: RawActor | null;
  repository?: { nameWithOwner?: string | null } | null;
  labels?: RawSearch<RawLabel> | null;
  comments?: RawSearch<RawComment> | null;
}

interface RawPullRequest {
  id?: string | null;
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
  reviewThreads?: RawSearch<RawThread> | null;
  reviews?: RawSearch<RawReview> | null;
  comments?: RawSearch<RawComment> | null;
  statusCheckRollup?: RawStatusCheckRollup | null;
}

interface RawLabel {
  name?: string | null;
}

interface RawStatusCheckRollup {
  state?: string | null;
  contexts?: RawSearch<RawCheckContext> | null;
}

interface RawDiscoveryNode {
  id?: string | null;
  number?: number | null;
  createdAt?: string | null;
  updatedAt?: string | null;
  repository?: { nameWithOwner?: string | null } | null;
}

interface RawPageInfo {
  endCursor?: string | null;
  hasNextPage?: boolean | null;
}

interface RawSearch<T> {
  nodes?: Array<T | null> | null;
  pageInfo?: RawPageInfo | null;
}

interface RawGraphqlData {
  viewer?: { login?: string | null } | null;
  rateLimit?: {
    cost?: number | null;
    remaining?: number | null;
    resetAt?: string | null;
  } | null;
  prsInvolved?: RawSearch<RawPullRequest> | null;
  issuesInvolved?: RawSearch<RawIssue> | null;
  // watchedPrs0, watchedIssues0, … — the count depends on the watch list.
  [alias: string]: unknown;
}

interface RawGraphqlResponse {
  data?: RawGraphqlData | null;
  errors?: Array<{ message?: string | null }> | null;
}

export interface GraphqlRunner {
  (query: string): Promise<string>;
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

function reviewState(
  state: string | null | undefined,
): GitHubReviewState | null {
  switch (state) {
    case "APPROVED":
    case "CHANGES_REQUESTED":
    case "COMMENTED":
    case "DISMISSED":
      return state;
    default:
      return null;
  }
}

function parseReview(review: RawReview | null): GitHubReview | null {
  if (
    review === null ||
    review.id === undefined ||
    review.id === null ||
    review.submittedAt === undefined ||
    review.submittedAt === null
  ) {
    return null;
  }
  const state = reviewState(review.state);
  if (state === null) return null;
  return {
    id: review.id,
    author: parseActor(review.author),
    body: review.body ?? "",
    state,
    submittedAt: review.submittedAt,
    url: review.url ?? "",
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
  const reviews = (raw.reviews?.nodes ?? [])
    .map(parseReview)
    .filter((review): review is GitHubReview => review !== null);
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
    comments,
    reviewThreads,
    reviews,
  };
}

// One target can arrive from several searches; merge rather than duplicate.
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

// The watch aliases are generated, so they are collected by prefix rather
// than named. Their source marks the target as watched, which is what turns
// a newly-opened target into an item.
function watchSearches<T>(
  data: RawGraphqlData,
  prefix: string,
): Array<{ source: string; search: RawSearch<T> | null | undefined }> {
  return Object.keys(data)
    .filter((key) => key.startsWith(prefix))
    .map((key) => ({
      source: "watched",
      search: data[key] as RawSearch<T> | null | undefined,
    }));
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

function parseGraphqlData(stdout: string): RawGraphqlData {
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
  return data;
}

function viewerLogin(data: RawGraphqlData): string {
  const username = data.viewer?.login;
  if (username === undefined || username === null || username === "") {
    throw new Error("GitHub GraphQL: viewer login was missing");
  }
  return username;
}

export function parseGithubResponse(
  stdout: string,
  requestDurationMs: number,
  fetchedAt = new Date().toISOString(),
): GitHubSnapshot {
  const data = parseGraphqlData(stdout);
  const username = viewerLogin(data);
  return {
    username,
    fetchedAt,
    requestDurationMs,
    rateLimit: parseRateLimit(data.rateLimit),
    targets: mergeTargets(
      [
        { source: "involved", search: data.prsInvolved },
        ...watchSearches<RawPullRequest>(data, "watchedPrs"),
      ],
      [
        { source: "involved", search: data.issuesInvolved },
        ...watchSearches<RawIssue>(data, "watchedIssues"),
      ],
    ),
  };
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

export function githubTargetKey(
  target: Pick<GitHubTarget, "kind" | "repository" | "number">,
): string {
  return `${target.kind}:${target.repository}#${target.number}`;
}

function readPage<T>(
  value: RawSearch<T> | null | undefined,
  label: string,
): { nodes: Array<T | null>; pageInfo: RawPageInfo } {
  if (value === null || value === undefined) {
    throw new Error(`GitHub GraphQL: ${label} was missing`);
  }
  const nodes = value.nodes;
  const pageInfo = value.pageInfo;
  if (!Array.isArray(nodes)) {
    throw new Error(`GitHub GraphQL: ${label}.nodes was missing`);
  }
  if (
    pageInfo === null ||
    pageInfo === undefined ||
    typeof pageInfo.hasNextPage !== "boolean"
  ) {
    throw new Error(`GitHub GraphQL: ${label}.pageInfo was missing`);
  }
  return { nodes, pageInfo };
}

function nextCursor(
  label: string,
  previous: string | null,
  pageInfo: RawPageInfo,
): string | null {
  if (!pageInfo.hasNextPage) return null;
  const cursor = pageInfo.endCursor;
  if (typeof cursor !== "string" || cursor === "" || cursor === previous) {
    throw new Error(
      `GitHub GraphQL: ${label} returned an unusable page cursor`,
    );
  }
  return cursor;
}

function discoveredTarget(
  raw: RawDiscoveryNode | null,
  spec: DiscoverySpec,
): DiscoveredTarget | null {
  if (raw === null) return null;
  const id = raw.id;
  const repository = raw.repository?.nameWithOwner;
  const number = raw.number;
  const createdAt = raw.createdAt;
  const updatedAt = raw.updatedAt;
  if (
    typeof id !== "string" ||
    id === "" ||
    typeof repository !== "string" ||
    repository === "" ||
    typeof number !== "number" ||
    !Number.isInteger(number) ||
    typeof createdAt !== "string" ||
    typeof updatedAt !== "string" ||
    !Number.isFinite(Date.parse(createdAt)) ||
    !Number.isFinite(Date.parse(updatedAt))
  ) {
    throw new Error(
      `GitHub GraphQL: ${spec.alias} returned an incomplete target`,
    );
  }
  return {
    id,
    kind: spec.kind,
    repository,
    number,
    createdAt,
    updatedAt,
    searchSources: [spec.source],
  };
}

function mergeDiscoveredTarget(
  targets: Map<string, DiscoveredTarget>,
  target: DiscoveredTarget,
): void {
  const key = githubTargetKey(target);
  const previous = targets.get(key);
  if (previous === undefined) {
    targets.set(key, target);
    return;
  }
  if (previous.id !== target.id) {
    throw new Error(`GitHub GraphQL: ${key} changed node ids during discovery`);
  }
  if (Date.parse(target.updatedAt) > Date.parse(previous.updatedAt)) {
    previous.updatedAt = target.updatedAt;
  }
  previous.searchSources = [
    ...new Set([...previous.searchSources, ...target.searchSources]),
  ];
}

interface DiscoveryResult {
  username: string;
  rateLimit: RateLimit | null;
  targets: DiscoveredTarget[];
}

async function discoverTargets(
  watch: readonly string[],
  updatedSince: string | null,
  runQuery: GraphqlRunner,
): Promise<DiscoveryResult> {
  const specs = discoverySpecs(watch, updatedSince);
  const cursors = new Map<string, string | null>();
  const targets = new Map<string, DiscoveredTarget>();
  let activeSpecs = specs;
  let username: string | null = null;
  let rateLimit: RateLimit | null = null;

  while (activeSpecs.length > 0) {
    const data = parseGraphqlData(
      await runQuery(buildDiscoveryQuery(activeSpecs, cursors)),
    );
    const pageUsername = viewerLogin(data);
    if (username !== null && username !== pageUsername) {
      throw new Error("GitHub GraphQL: viewer login changed during sync");
    }
    username = pageUsername;
    rateLimit = parseRateLimit(data.rateLimit) ?? rateLimit;

    const nextSpecs: DiscoverySpec[] = [];
    for (const spec of activeSpecs) {
      const page = readPage<RawDiscoveryNode>(
        data[spec.alias] as RawSearch<RawDiscoveryNode> | null | undefined,
        `search ${spec.alias}`,
      );
      for (const raw of page.nodes) {
        const target = discoveredTarget(raw, spec);
        if (target !== null) mergeDiscoveredTarget(targets, target);
      }
      const cursor = nextCursor(
        `search ${spec.alias}`,
        cursors.get(spec.alias) ?? null,
        page.pageInfo,
      );
      if (cursor !== null) {
        cursors.set(spec.alias, cursor);
        nextSpecs.push(spec);
      }
    }
    activeSpecs = nextSpecs;
  }

  if (username === null) {
    throw new Error("GitHub GraphQL: discovery returned no pages");
  }
  const threshold = updatedSince === null ? null : Date.parse(updatedSince);
  if (threshold !== null && !Number.isFinite(threshold)) {
    throw new Error(`GitHub sync checkpoint is not a date: ${updatedSince}`);
  }
  return {
    username,
    rateLimit,
    targets: [...targets.values()].filter(
      (target) =>
        threshold === null || Date.parse(target.updatedAt) >= threshold,
    ),
  };
}

type DetailConnection =
  "comments" | "labels" | "reviewThreads" | "reviews" | "contexts";

function detailConnections(kind: DiscoveredTarget["kind"]): DetailConnection[] {
  return kind === "issue"
    ? ["comments", "labels"]
    : ["comments", "reviewThreads", "reviews", "contexts"];
}

function pageInfoFields(): string {
  return `pageInfo {
        endCursor
        hasNextPage
      }`;
}

function commentFields(): string {
  return `id
        author {
          login
          __typename
        }
        body
        createdAt
        url
        reactionGroups {
          viewerHasReacted
        }`;
}

function buildDetailQuery(
  target: DiscoveredTarget,
  active: ReadonlySet<DetailConnection>,
  cursors: ReadonlyMap<DetailConnection, string | null>,
): string {
  const comments = active.has("comments")
    ? `comments(
        first: ${DETAIL_PAGE_SIZE}
        after: ${cursorArgument(cursors.get("comments"))}
      ) {
        nodes {
          ${commentFields()}
        }
        ${pageInfoFields()}
      }`
    : "";

  const common = `id
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
      }`;

  let nodeFields: string;
  if (target.kind === "issue") {
    const labels = active.has("labels")
      ? `labels(
          first: ${DETAIL_PAGE_SIZE}
          after: ${cursorArgument(cursors.get("labels"))}
        ) {
          nodes {
            name
          }
          ${pageInfoFields()}
        }`
      : "";
    nodeFields = `... on Issue {
      ${common}
      ${labels}
      ${comments}
    }`;
  } else {
    const reviewThreads = active.has("reviewThreads")
      ? `reviewThreads(
          first: ${DETAIL_PAGE_SIZE}
          after: ${cursorArgument(cursors.get("reviewThreads"))}
        ) {
          nodes {
            id
            isResolved
          }
          ${pageInfoFields()}
        }`
      : "";
    const reviews = active.has("reviews")
      ? `reviews(
          first: ${DETAIL_PAGE_SIZE}
          after: ${cursorArgument(cursors.get("reviews"))}
        ) {
          nodes {
            id
            author {
              login
              __typename
            }
            body
            state
            submittedAt
            url
          }
          ${pageInfoFields()}
        }`
      : "";
    const contexts = active.has("contexts")
      ? `contexts(
            first: ${DETAIL_PAGE_SIZE}
            after: ${cursorArgument(cursors.get("contexts"))}
          ) {
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
            ${pageInfoFields()}
          }`
      : "";
    nodeFields = `... on PullRequest {
      ${common}
      isDraft
      additions
      deletions
      changedFiles
      headRefOid
      ${comments}
      ${reviewThreads}
      ${reviews}
      statusCheckRollup {
        state
        ${contexts}
      }
    }`;
  }

  return `query {
    viewer {
      login
    }
    rateLimit {
      cost
      remaining
      resetAt
    }
    node(id: ${graphqlString(target.id)}) {
      ${nodeFields}
    }
  }`;
}

function buildThreadCommentsQuery(
  threadId: string,
  cursor: string | null,
): string {
  return `query {
    viewer {
      login
    }
    rateLimit {
      cost
      remaining
      resetAt
    }
    node(id: ${graphqlString(threadId)}) {
      ... on PullRequestReviewThread {
        id
        isResolved
        comments(
          first: ${DETAIL_PAGE_SIZE}
          after: ${cursorArgument(cursor)}
        ) {
          nodes {
            ${commentFields()}
          }
          ${pageInfoFields()}
        }
      }
    }
  }`;
}

function detailNode(
  data: RawGraphqlData,
  target: DiscoveredTarget,
): RawIssue | RawPullRequest {
  const node = data["node"];
  if (!isRecord(node)) {
    throw new Error(
      `GitHub GraphQL: ${githubTargetKey(target)} disappeared during detail fetch`,
    );
  }
  return node as RawIssue | RawPullRequest;
}

function appendConnection<T>(
  previous: RawSearch<T> | null | undefined,
  current: RawSearch<T> | null | undefined,
): RawSearch<T> | null | undefined {
  if (current === undefined) return previous;
  if (current === null) return null;
  return {
    ...current,
    nodes: [...(previous?.nodes ?? []), ...(current.nodes ?? [])],
  };
}

function mergeIssuePage(
  previous: RawIssue | undefined,
  current: RawIssue,
): RawIssue {
  const merged: RawIssue = { ...(previous ?? {}), ...current };
  if (current.comments !== undefined) {
    merged.comments = appendConnection(previous?.comments, current.comments);
  }
  if (current.labels !== undefined) {
    merged.labels = appendConnection(previous?.labels, current.labels);
  }
  return merged;
}

function mergePullRequestPage(
  previous: RawPullRequest | undefined,
  current: RawPullRequest,
): RawPullRequest {
  const merged: RawPullRequest = { ...(previous ?? {}), ...current };
  if (current.comments !== undefined) {
    merged.comments = appendConnection(previous?.comments, current.comments);
  }
  if (current.reviewThreads !== undefined) {
    merged.reviewThreads = appendConnection(
      previous?.reviewThreads,
      current.reviewThreads,
    );
  }
  if (current.reviews !== undefined) {
    merged.reviews = appendConnection(previous?.reviews, current.reviews);
  }
  if (current.statusCheckRollup !== undefined) {
    if (current.statusCheckRollup === null) {
      merged.statusCheckRollup = null;
    } else {
      const previousRollup = previous?.statusCheckRollup;
      const currentRollup = current.statusCheckRollup;
      const mergedRollup: RawStatusCheckRollup = {
        ...(previousRollup ?? {}),
        ...currentRollup,
      };
      if (currentRollup.contexts !== undefined) {
        mergedRollup.contexts = appendConnection(
          previousRollup?.contexts,
          currentRollup.contexts,
        );
      }
      merged.statusCheckRollup = mergedRollup;
    }
  }
  return merged;
}

async function fetchThreadComments(
  threadId: string,
  runQuery: GraphqlRunner,
): Promise<{ thread: RawThread; rateLimit: RateLimit | null }> {
  let cursor: string | null = null;
  const comments: Array<RawComment | null> = [];
  let isResolved = false;
  let rateLimit: RateLimit | null = null;

  while (true) {
    const data = parseGraphqlData(
      await runQuery(buildThreadCommentsQuery(threadId, cursor)),
    );
    viewerLogin(data);
    rateLimit = parseRateLimit(data.rateLimit) ?? rateLimit;
    const node = data["node"];
    if (!isRecord(node)) {
      throw new Error(
        `GitHub GraphQL: review thread ${threadId} disappeared during detail fetch`,
      );
    }
    const rawThread = node as RawThread;
    if (rawThread.id !== threadId) {
      throw new Error(`GitHub GraphQL: review thread ${threadId} changed id`);
    }
    const page = readPage<RawComment>(
      rawThread.comments,
      `review thread ${threadId} comments`,
    );
    comments.push(...page.nodes);
    isResolved = rawThread.isResolved === true;
    const next = nextCursor(
      `review thread ${threadId} comments`,
      cursor,
      page.pageInfo,
    );
    if (next === null) break;
    cursor = next;
  }

  return {
    thread: {
      id: threadId,
      isResolved,
      comments: { nodes: comments },
    },
    rateLimit,
  };
}

async function fetchTargetDetails(
  target: DiscoveredTarget,
  runQuery: GraphqlRunner,
): Promise<{ target: GitHubTarget; rateLimit: RateLimit | null }> {
  const active = new Set<DetailConnection>(detailConnections(target.kind));
  const cursors = new Map<DetailConnection, string | null>();
  let raw: RawIssue | RawPullRequest | undefined;
  let rateLimit: RateLimit | null = null;

  while (active.size > 0) {
    const data = parseGraphqlData(
      await runQuery(buildDetailQuery(target, active, cursors)),
    );
    viewerLogin(data);
    rateLimit = parseRateLimit(data.rateLimit) ?? rateLimit;
    const current = detailNode(data, target);
    const pageInfos = new Map<DetailConnection, RawPageInfo>();

    if (target.kind === "issue") {
      const issue = current as RawIssue;
      if (active.has("comments")) {
        pageInfos.set(
          "comments",
          readPage(issue.comments, `${githubTargetKey(target)} comments`)
            .pageInfo,
        );
      }
      if (active.has("labels")) {
        pageInfos.set(
          "labels",
          readPage(issue.labels, `${githubTargetKey(target)} labels`).pageInfo,
        );
      }
      raw = mergeIssuePage(raw as RawIssue | undefined, issue);
    } else {
      const pullRequest = current as RawPullRequest;
      if (active.has("comments")) {
        pageInfos.set(
          "comments",
          readPage(pullRequest.comments, `${githubTargetKey(target)} comments`)
            .pageInfo,
        );
      }
      if (active.has("reviewThreads")) {
        pageInfos.set(
          "reviewThreads",
          readPage(
            pullRequest.reviewThreads,
            `${githubTargetKey(target)} review threads`,
          ).pageInfo,
        );
      }
      if (active.has("reviews")) {
        pageInfos.set(
          "reviews",
          readPage(pullRequest.reviews, `${githubTargetKey(target)} reviews`)
            .pageInfo,
        );
      }
      if (active.has("contexts")) {
        const rollup = pullRequest.statusCheckRollup;
        if (rollup === null || rollup === undefined) {
          active.delete("contexts");
        } else {
          pageInfos.set(
            "contexts",
            readPage(
              rollup.contexts,
              `${githubTargetKey(target)} status contexts`,
            ).pageInfo,
          );
        }
      }
      raw = mergePullRequestPage(
        raw as RawPullRequest | undefined,
        pullRequest,
      );
    }

    for (const [connection, pageInfo] of pageInfos) {
      const next = nextCursor(
        `${githubTargetKey(target)} ${connection}`,
        cursors.get(connection) ?? null,
        pageInfo,
      );
      if (next === null) {
        active.delete(connection);
      } else {
        cursors.set(connection, next);
      }
    }
  }

  if (raw === undefined) {
    throw new Error(`GitHub GraphQL: ${githubTargetKey(target)} had no detail`);
  }

  if (target.kind === "pull_request") {
    const pullRequest = raw as RawPullRequest;
    for (const thread of pullRequest.reviewThreads?.nodes ?? []) {
      if (thread === null || thread.id === undefined || thread.id === null) {
        throw new Error(
          `GitHub GraphQL: ${githubTargetKey(target)} returned an incomplete review thread`,
        );
      }
      const comments = await fetchThreadComments(thread.id, runQuery);
      rateLimit = comments.rateLimit ?? rateLimit;
      thread.isResolved = comments.thread.isResolved;
      thread.comments = comments.thread.comments;
    }
  }

  const source = target.searchSources[0] ?? "involved";
  const parsed =
    target.kind === "issue"
      ? parseIssue(raw as RawIssue, source)
      : parsePullRequest(raw as RawPullRequest, source);
  if (parsed === null) {
    throw new Error(
      `GitHub GraphQL: ${githubTargetKey(target)} had incomplete detail`,
    );
  }
  if (githubTargetKey(parsed) !== githubTargetKey(target)) {
    throw new Error(
      `GitHub GraphQL: detail did not match ${githubTargetKey(target)}`,
    );
  }
  parsed.searchSources = [...target.searchSources];
  return { target: parsed, rateLimit };
}

function normalizedTimestamp(value: string, label: string): string {
  const timestamp = Date.parse(value);
  if (!Number.isFinite(timestamp)) {
    throw new Error(`GitHub ${label} is not a date: ${value}`);
  }
  return new Date(timestamp).toISOString();
}

export async function fetchGithubSync(
  options: GithubSyncOptions = {},
  runQuery: GraphqlRunner = runGhGraphql,
): Promise<GithubSyncResult> {
  const startedAt = normalizedTimestamp(
    options.startedAt ?? new Date().toISOString(),
    "sync start",
  );
  const fullReconciliation =
    options.fullReconciliation === true ||
    options.since === null ||
    options.since === undefined;
  const since =
    fullReconciliation || options.since === null || options.since === undefined
      ? null
      : normalizedTimestamp(options.since, "sync checkpoint");
  const updatedSince =
    since === null
      ? null
      : new Date(Date.parse(since) - SYNC_LOOKBACK_MS).toISOString();
  const started = performance.now();
  const discovery = await discoverTargets(
    options.watch ?? [],
    updatedSince,
    runQuery,
  );
  const targets: GitHubTarget[] = [];
  let rateLimit = discovery.rateLimit;
  for (const candidate of discovery.targets) {
    const detail = await fetchTargetDetails(candidate, runQuery);
    targets.push(detail.target);
    rateLimit = detail.rateLimit ?? rateLimit;
  }
  return {
    snapshot: {
      username: discovery.username,
      fetchedAt: new Date().toISOString(),
      requestDurationMs: Math.round(performance.now() - started),
      rateLimit,
      targets,
    },
    refreshedTargetKeys: discovery.targets.map(githubTargetKey),
    fullReconciliation,
    processedThrough: startedAt,
  };
}

async function runGhGraphql(query: string): Promise<string> {
  try {
    const result = await execFileAsync(
      "gh",
      ["api", "graphql", "--field", `query=${query}`],
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
