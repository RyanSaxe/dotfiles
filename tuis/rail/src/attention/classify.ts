import {
  actorIsEligible,
  normalizeLogin,
  type AttentionConfig,
} from "./config.js";
import type {
  AttentionItem,
  GitHubComment,
  PullRequestSnapshot,
  ReviewThread,
} from "./types.js";

function escapeRegExp(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

export function mentionsViewer(body: string, username: string): boolean {
  const login = normalizeLogin(username);
  if (!login) return false;
  const boundary = new RegExp(
    `(^|[\\s([{@])@${escapeRegExp(login)}(?=$|[\\s.,!?;:)\\]}])`,
    "i",
  );
  return boundary.test(body);
}

function latestComment(comments: GitHubComment[]): GitHubComment | null {
  return comments.reduce<GitHubComment | null>(
    (latest, comment) =>
      latest === null || comment.createdAt > latest.createdAt
        ? comment
        : latest,
    null,
  );
}

function isViewerComment(comment: GitHubComment, username: string): boolean {
  return (
    comment.author !== null &&
    normalizeLogin(comment.author.login) === normalizeLogin(username)
  );
}

function participated(comments: GitHubComment[], username: string): boolean {
  return comments.some(
    (comment) =>
      isViewerComment(comment, username) ||
      mentionsViewer(comment.body, username),
  );
}

function itemFromComment(
  pr: PullRequestSnapshot,
  kind: "review_comment" | "conversation",
  comment: GitHubComment,
  id: string,
): AttentionItem {
  return {
    id,
    kind,
    repository: pr.repository,
    number: pr.number,
    title: pr.title,
    url: pr.url,
    summary: comment.body.replace(/\s+/g, " ").trim() || "New GitHub comment",
    actor: comment.author,
    createdAt: comment.createdAt,
    priority: "normal",
  };
}

function classifyCommentSet(
  pr: PullRequestSnapshot,
  comments: GitHubComment[],
  username: string,
  config: AttentionConfig,
  kind: "review_comment" | "conversation",
  idPrefix: string,
): AttentionItem | null {
  const meaningful = comments.filter((comment) =>
    actorIsEligible(comment.author, config),
  );
  const last = latestComment(meaningful);
  if (
    last === null ||
    isViewerComment(last, username) ||
    last.viewerHasReacted
  ) {
    return null;
  }

  const ownPr =
    pr.author !== null &&
    normalizeLogin(pr.author.login) === normalizeLogin(username);
  if (!ownPr && !participated(meaningful, username)) return null;

  return itemFromComment(pr, kind, last, `${idPrefix}:${last.id}`);
}

export function classifyPullRequest(
  pr: PullRequestSnapshot,
  username: string,
  config: AttentionConfig,
): AttentionItem[] {
  const items: AttentionItem[] = [];

  for (const thread of pr.reviewThreads) {
    if (thread.isResolved) continue;
    const item = classifyCommentSet(
      pr,
      thread.comments,
      username,
      config,
      "review_comment",
      `review:${thread.id}`,
    );
    if (item !== null) items.push(item);
  }

  const conversation = classifyCommentSet(
    pr,
    pr.comments,
    username,
    config,
    "conversation",
    `conversation:${pr.repository}#${pr.number}`,
  );
  if (conversation !== null) items.push(conversation);

  if (pr.reviewRequested) {
    const fingerprint = pr.reviewRequestFingerprint || "viewer";
    items.push({
      id: `review-request:${pr.repository}#${pr.number}:${fingerprint}`,
      kind: "review_request",
      repository: pr.repository,
      number: pr.number,
      title: pr.title,
      url: pr.url,
      summary: "GitHub requested your review",
      actor: null,
      createdAt: pr.updatedAt,
      priority: "high",
    });
  }

  return items;
}

export function meaningfulComments(
  comments: GitHubComment[],
  config: AttentionConfig,
): GitHubComment[] {
  return comments.filter((comment) => actorIsEligible(comment.author, config));
}

export function reviewThreadIsActionable(
  thread: ReviewThread,
  pr: PullRequestSnapshot,
  username: string,
  config: AttentionConfig,
): boolean {
  if (thread.isResolved) return false;
  return (
    classifyCommentSet(
      pr,
      thread.comments,
      username,
      config,
      "review_comment",
      `review:${thread.id}`,
    ) !== null
  );
}
