import {
  actorIsEligible,
  normalizeLogin,
  type AttentionConfig,
} from "./config.js";
import { reviewContext } from "./context.js";
import type {
  AttentionItem,
  GitHubComment,
  GitHubTarget,
  PullRequestTarget,
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
  target: GitHubTarget,
  kind: "review_comment" | "conversation",
  comment: GitHubComment,
  id: string,
): AttentionItem {
  return {
    id,
    kind,
    targetKind: target.kind,
    repository: target.repository,
    number: target.number,
    title: target.title,
    url: target.url,
    summary: comment.body.replace(/\s+/g, " ").trim() || "New GitHub comment",
    actor: comment.author,
    createdAt: comment.createdAt,
    priority: "normal",
    context: reviewContext(target),
  };
}

function classifyCommentSet(
  target: GitHubTarget,
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

  const owned =
    target.author !== null &&
    normalizeLogin(target.author.login) === normalizeLogin(username);
  if (!owned && !participated(meaningful, username)) return null;

  return itemFromComment(target, kind, last, `${idPrefix}:${last.id}`);
}

// One classifier for both kinds. A PR adds review threads and review
// requests on top; everything else — comments, mentions, participation,
// ownership, clearing — is identical, so it is written once.
export function classifyTarget(
  target: GitHubTarget,
  username: string,
  config: AttentionConfig,
): AttentionItem[] {
  const items: AttentionItem[] = [];

  if (target.kind === "pull_request") {
    for (const thread of target.reviewThreads) {
      if (thread.isResolved) continue;
      const item = classifyCommentSet(
        target,
        thread.comments,
        username,
        config,
        "review_comment",
        `review:${thread.id}`,
      );
      if (item !== null) items.push(item);
    }
  }

  const conversation = classifyCommentSet(
    target,
    target.comments,
    username,
    config,
    "conversation",
    `conversation:${target.repository}#${target.number}`,
  );
  if (conversation !== null) items.push(conversation);

  if (target.kind === "pull_request" && target.reviewRequested) {
    const fingerprint = target.reviewRequestFingerprint || "viewer";
    items.push({
      id: `review-request:${target.repository}#${target.number}:${fingerprint}`,
      kind: "review_request",
      targetKind: "pull_request",
      repository: target.repository,
      number: target.number,
      title: target.title,
      url: target.url,
      summary: "GitHub requested your review",
      actor: null,
      createdAt: target.updatedAt,
      priority: "high",
      context: reviewContext(target),
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
  pr: PullRequestTarget,
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
