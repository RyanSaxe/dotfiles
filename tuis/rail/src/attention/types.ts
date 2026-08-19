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

export interface PullRequestSnapshot {
  repository: string;
  number: number;
  title: string;
  url: string;
  updatedAt: string;
  headSha: string;
  author: GitHubActor | null;
  ciState: CiState;
  searchSources: string[];
  reviewRequested: boolean;
  reviewRequestFingerprint: string;
  comments: GitHubComment[];
  reviewThreads: ReviewThread[];
}

export type AttentionKind =
  "review_comment" | "conversation" | "review_request" | "ci";

export interface AttentionItem {
  id: string;
  kind: AttentionKind;
  repository: string;
  number: number;
  title: string;
  url: string;
  summary: string;
  actor: GitHubActor | null;
  createdAt: string;
  priority: "normal" | "high";
}

export interface CiMemory {
  state: CiState;
  headSha: string;
  red: boolean;
  redEpoch: number;
}

export interface RateLimit {
  cost: number;
  remaining: number;
  resetAt: string;
}

export interface ObserverState {
  version: 1;
  lastAttemptAt: string | null;
  lastSuccessfulSyncAt: string | null;
  lastError: string | null;
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
  pullRequests: PullRequestSnapshot[];
}
