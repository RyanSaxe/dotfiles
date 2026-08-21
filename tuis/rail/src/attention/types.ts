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
  reviewRequested: boolean;
  reviewRequestFingerprint: string;
  reviewThreads: ReviewThread[];
}

export interface IssueTarget extends TargetBase {
  kind: "issue";
  labels: string[];
}

export type GitHubTarget = PullRequestTarget | IssueTarget;

export type AttentionKind =
  "review_comment" | "conversation" | "review_request" | "ci" | "opened";

export interface AttentionItem {
  id: string;
  kind: AttentionKind;
  // Which object this is about. Carried separately from `kind` so the reason
  // and the object stay independent — an issue comment and a PR comment are
  // the same reason on different objects, and only the object picks the hue.
  targetKind: TargetKind;
  repository: string;
  number: number;
  title: string;
  url: string;
  summary: string;
  actor: GitHubActor | null;
  createdAt: string;
  priority: "normal" | "high";
  context?: ReviewContext;
}

export interface CiMemory {
  state: CiState;
  headSha: string;
  red: boolean;
  redEpoch: number;
}

export interface CiTransition {
  memory: CiMemory;
  item: AttentionItem | null;
  newlyRed: boolean;
}

export interface RateLimit {
  cost: number;
  remaining: number;
  resetAt: string;
}

export interface ObserverState {
  version: 1;
  // The authenticated login, kept so readers can tell "you" from everyone
  // else without a network call. Optional: state written before this
  // existed is still valid.
  username?: string;
  lastAttemptAt: string | null;
  lastSuccessfulSyncAt: string | null;
  lastError: string | null;
  // The notification transport is downstream of attention data. Its failures
  // are recorded here so they can never be mistaken for a GitHub failure,
  // never back off polling, and never reach the Reviews table.
  lastNotifyError?: string | null;
  consecutiveFailures: number;
  retryAfter: string | null;
  rateLimit: RateLimit | null;
  items: Record<string, AttentionItem>;
  acknowledged: Record<string, string>;
  notified: Record<string, string>;
  ci: Record<string, CiMemory>;
}

export interface GitHubSnapshot {
  username: string;
  fetchedAt: string;
  requestDurationMs: number;
  rateLimit: RateLimit | null;
  targets: GitHubTarget[];
}
