export type ActorKind = "user" | "bot" | "app" | "unknown";

export interface GitHubActor {
  login: string;
  kind: ActorKind;
}

export interface GitHubComment {
  id: string;
  author: GitHubActor | null;
  body: string;
  createdAt: string;
  url: string;
  viewerHasReacted: boolean;
}

export interface ReviewThread {
  id: string;
  isResolved: boolean;
  comments: GitHubComment[];
}

export type GitHubReviewState =
  "APPROVED" | "CHANGES_REQUESTED" | "COMMENTED" | "DISMISSED";

export interface GitHubReview {
  id: string;
  author: GitHubActor | null;
  body: string;
  state: GitHubReviewState;
  submittedAt: string;
  url: string;
}

export type CiState =
  | "SUCCESS"
  | "FAILURE"
  | "ERROR"
  | "PENDING"
  | "EXPECTED"
  | "NEUTRAL"
  | "UNKNOWN";

// Context retained with an attention item so the dashboard can explain why a
// target needs attention without making its own network request.
export interface ReviewContext {
  body: string;
  author: GitHubActor | null;
  ciState: CiState;
  // Only the checks that failed. A green check on a red PR is noise on a row
  // you are looking at precisely because something broke.
  failingChecks: string[];
  // Scannable shape of the target: diff size for a PR, labels for an issue.
  additions: number;
  deletions: number;
  changedFiles: number;
  labels: string[];
}

export type TargetKind = "pull_request" | "issue";

// One target model for both kinds. Everything a PR and an issue genuinely
// share lives here; the union below adds only what the underlying GitHub
// object actually differs on.
interface TargetBase {
  repository: string;
  number: number;
  title: string;
  body: string;
  url: string;
  createdAt: string;
  updatedAt: string;
  author: GitHubActor | null;
  searchSources: string[];
  comments: GitHubComment[];
}

export interface PullRequestTarget extends TargetBase {
  kind: "pull_request";
  isDraft: boolean;
  additions: number;
  deletions: number;
  changedFiles: number;
  headSha: string;
  ciState: CiState;
  failingChecks: string[];
  reviewThreads: ReviewThread[];
  reviews: GitHubReview[];
}

export interface IssueTarget extends TargetBase {
  kind: "issue";
  labels: string[];
}

export type GitHubTarget = PullRequestTarget | IssueTarget;

export type AttentionKind = "comment" | "ci" | "opened" | "review";

export interface AttentionReason {
  // The stable event identity lets a target row become active again when a
  // later event replaces the one that was acknowledged.
  id: string;
  kind: AttentionKind;
  summary: string;
  actor: GitHubActor | null;
  createdAt: string;
  priority: "normal" | "high";
  reviewState?: GitHubReviewState;
}

export interface AttentionItem {
  // One row per GitHub target. This is deliberately not a comment or thread
  // id: new activity updates this row instead of adding another one.
  id: string;
  targetKind: TargetKind;
  repository: string;
  number: number;
  title: string;
  url: string;
  // Reasons are kept together so CI and comment activity can share one row.
  reasons: AttentionReason[];
  // The sorted reason ids form the current activity revision. Acknowledgement
  // remains valid while current reasons are a subset of that revision.
  activityKey: string;
  context?: ReviewContext;
}

export interface CiMemory {
  state: CiState;
  headSha: string;
  red: boolean;
  redEpoch: number;
  // A red state discovered before the initial baseline is remembered but does
  // not become an alert later merely because the target was refreshed.
  alerted: boolean;
}

export interface CiTransition {
  memory: CiMemory;
  reason: AttentionReason | null;
  newlyRed: boolean;
}

// This is a time boundary in GitHub's updated-activity stream. It is not a
// GraphQL page cursor. Cursors are valid for walking one response and are not
// durable change-feed positions.
export interface GithubSyncCheckpoint {
  processedThrough: string | null;
  lastFullReconciliationAt: string | null;
}

export interface RateLimit {
  cost: number;
  remaining: number;
  resetAt: string;
}

export interface ObserverState {
  version: 2;
  // The authenticated login, kept so readers can tell "you" from everyone
  // else without a network call. Optional: state written before this
  // existed is still valid.
  username?: string;
  lastAttemptAt: string | null;
  lastSuccessfulSyncAt: string | null;
  lastError: string | null;
  consecutiveFailures: number;
  retryAfter: string | null;
  rateLimit: RateLimit | null;
  items: Record<string, AttentionItem>;
  // Maps a stable target id to the reason ids the user dismissed.
  acknowledged: Record<string, string>;
  ci: Record<string, CiMemory>;
  // The first successful sync establishes this boundary. Activity before it
  // is historical state, not a new Rail item.
  baselineAt: string | null;
  githubSync?: GithubSyncCheckpoint;
  // When each currently watched repository was first seen. Only activity after
  // that moment is reported for watched-only targets.
  watchedSince?: Record<string, string>;
}

export interface GitHubSnapshot {
  username: string;
  fetchedAt: string;
  requestDurationMs: number;
  rateLimit: RateLimit | null;
  targets: GitHubTarget[];
}
