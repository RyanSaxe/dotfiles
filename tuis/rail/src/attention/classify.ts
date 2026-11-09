import {
  actorIsEligible,
  normalizeLogin,
  type AttentionConfig,
} from "./config.js";
import { reviewContext } from "./context.js";
import type {
  AttentionItem,
  AttentionReason,
  GitHubComment,
  GitHubActor,
  GitHubReview,
  GitHubTarget,
} from "./types.js";

export interface ClassificationOptions {
  // Historical activity before this boundary is never promoted into the
  // inbox. Once established, the boundary remains in observer state.
  baselineAt?: string | null;
  // Applies to watched targets that are not already account-wide targets
  // through ownership or direct participation.
  watchedSince?: string;
}

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

function timestamp(value: string, label: string): number {
  const parsed = Date.parse(value);
  if (!Number.isFinite(parsed)) {
    throw new Error(`GitHub ${label} is not a date: ${value}`);
  }
  return parsed;
}

function floorTimestamp(
  value: string | null | undefined,
  label: string,
): number | null {
  return value === undefined || value === null ? null : timestamp(value, label);
}

function atOrAfter(
  value: string,
  floor: number | null,
  label: string,
): boolean {
  return floor === null || timestamp(value, label) >= floor;
}

function latestComment(comments: GitHubComment[]): GitHubComment | null {
  return comments.reduce<GitHubComment | null>((latest, comment) => {
    if (latest === null) return comment;
    const order = comment.createdAt.localeCompare(latest.createdAt);
    return order > 0 || (order === 0 && comment.id > latest.id)
      ? comment
      : latest;
  }, null);
}

function latestReview(reviews: GitHubReview[]): GitHubReview | null {
  return reviews.reduce<GitHubReview | null>((latest, review) => {
    if (latest === null) return review;
    const order = review.submittedAt.localeCompare(latest.submittedAt);
    return order > 0 || (order === 0 && review.id > latest.id)
      ? review
      : latest;
  }, null);
}

function isViewerActor(actor: GitHubActor | null, username: string): boolean {
  return (
    actor !== null && normalizeLogin(actor.login) === normalizeLogin(username)
  );
}

function isViewerComment(comment: GitHubComment, username: string): boolean {
  return isViewerActor(comment.author, username);
}

function uniqueComments(target: GitHubTarget): GitHubComment[] {
  const comments = [...target.comments];
  if (target.kind === "pull_request") {
    for (const thread of target.reviewThreads) {
      comments.push(...thread.comments);
    }
  }
  const byId = new Map<string, GitHubComment>();
  for (const comment of comments) byId.set(comment.id, comment);
  return [...byId.values()];
}

function participated(
  comments: GitHubComment[],
  username: string,
  config: AttentionConfig,
): boolean {
  return comments.some(
    (comment) =>
      isViewerComment(comment, username) ||
      (actorIsEligible(comment.author, config) &&
        mentionsViewer(comment.body, username)),
  );
}

function targetIsOwned(target: GitHubTarget, username: string): boolean {
  return (
    target.author !== null &&
    normalizeLogin(target.author.login) === normalizeLogin(username)
  );
}

function targetIsWatched(target: GitHubTarget): boolean {
  return target.searchSources.includes("watched");
}

function commentFloor(
  target: GitHubTarget,
  options: ClassificationOptions,
  accountWide: boolean,
): number | null {
  const floors = [
    floorTimestamp(options.baselineAt, "attention baseline"),
  ].filter((floor): floor is number => floor !== null);
  if (targetIsWatched(target) && !accountWide) {
    const watched = floorTimestamp(options.watchedSince, "watch start");
    if (watched !== null) floors.push(watched);
  }
  return floors.length === 0 ? null : Math.max(...floors);
}

function commentReason(
  target: GitHubTarget,
  username: string,
  config: AttentionConfig,
  floor: number | null,
): AttentionReason | null {
  const meaningful = uniqueComments(target).filter(
    (comment) =>
      isViewerComment(comment, username) ||
      actorIsEligible(comment.author, config),
  );
  const recent = meaningful.filter((comment) =>
    atOrAfter(comment.createdAt, floor, "comment"),
  );
  const external = recent.filter(
    (comment) =>
      !isViewerComment(comment, username) &&
      actorIsEligible(comment.author, config),
  );
  const latestExternal = latestComment(external);
  if (latestExternal === null) return null;

  // A direct reply or a reaction handles all activity up to that point. A
  // later external comment remains visible even when an older one was reacted
  // to.
  const latestAction = latestComment(
    recent.filter(
      (comment) =>
        isViewerComment(comment, username) || comment.viewerHasReacted,
    ),
  );
  if (
    latestAction !== null &&
    timestamp(latestAction.createdAt, "comment") >=
      timestamp(latestExternal.createdAt, "comment")
  ) {
    return null;
  }

  return {
    id: `comment:${latestExternal.id}`,
    kind: "comment",
    summary:
      latestExternal.body.replace(/\s+/g, " ").trim() || "New GitHub comment",
    actor: latestExternal.author,
    createdAt: latestExternal.createdAt,
    priority: "normal",
  };
}

function reviewVerb(state: GitHubReview["state"]): string {
  switch (state) {
    case "APPROVED":
      return "Approved review";
    case "CHANGES_REQUESTED":
      return "Changes requested";
    case "COMMENTED":
      return "Submitted review";
    case "DISMISSED":
      return "Dismissed review";
  }
}

function reviewReason(
  target: GitHubTarget,
  username: string,
  config: AttentionConfig,
  floor: number | null,
): AttentionReason | null {
  if (target.kind !== "pull_request" || !targetIsOwned(target, username)) {
    return null;
  }
  const recent = target.reviews.filter(
    (review) =>
      review.state !== "DISMISSED" &&
      review.author !== null &&
      !isViewerActor(review.author, username) &&
      actorIsEligible(review.author, config) &&
      atOrAfter(review.submittedAt, floor, "review"),
  );
  const latest = latestReview(recent);
  if (latest === null) return null;

  const body = latest.body.replace(/\s+/g, " ").trim();
  return {
    id: `review:${latest.id}`,
    kind: "review",
    reviewState: latest.state,
    summary:
      body === ""
        ? reviewVerb(latest.state)
        : `${reviewVerb(latest.state)}: ${body}`,
    actor: latest.author,
    createdAt: latest.submittedAt,
    priority: latest.state === "CHANGES_REQUESTED" ? "high" : "normal",
  };
}

function openedReason(
  target: GitHubTarget,
  username: string,
  config: AttentionConfig,
  watchedSince: string | undefined,
): AttentionReason | null {
  const floor = floorTimestamp(watchedSince, "watch start");
  if (!targetIsWatched(target) || floor === null) return null;
  const createdAt = timestamp(target.createdAt, "target creation");
  if (createdAt < floor) return null;
  if (target.kind === "pull_request" && target.isDraft) return null;
  if (target.author === null || targetIsOwned(target, username)) return null;
  if (!actorIsEligible(target.author, config)) return null;

  const latestAction = latestComment(
    uniqueComments(target).filter(
      (comment) =>
        (isViewerComment(comment, username) ||
          actorIsEligible(comment.author, config)) &&
        (isViewerComment(comment, username) || comment.viewerHasReacted),
    ),
  );
  if (
    latestAction !== null &&
    timestamp(latestAction.createdAt, "comment") >= createdAt
  ) {
    return null;
  }

  return {
    id: `opened:${target.kind}:${target.repository}#${target.number}`,
    kind: "opened",
    summary:
      target.kind === "issue"
        ? "New issue in a watched repository"
        : "New pull request in a watched repository",
    actor: target.author,
    createdAt: target.createdAt,
    priority: "normal",
  };
}

function reasonOrder(a: AttentionReason, b: AttentionReason): number {
  if (a.priority !== b.priority) return a.priority === "high" ? -1 : 1;
  const byTime = b.createdAt.localeCompare(a.createdAt);
  return byTime !== 0 ? byTime : a.id.localeCompare(b.id);
}

export function attentionItem(
  target: GitHubTarget,
  reasons: readonly AttentionReason[],
): AttentionItem {
  if (reasons.length === 0) {
    throw new Error("cannot create attention item without a reason");
  }
  const ordered = [...reasons].sort(reasonOrder);
  return {
    id: `${target.kind}:${target.repository}#${target.number}`,
    targetKind: target.kind,
    repository: target.repository,
    number: target.number,
    title: target.title,
    url: target.url,
    reasons: ordered,
    activityKey: ordered
      .map((reason) => reason.id)
      .sort()
      .join("|"),
    context: reviewContext(target),
  };
}

// One row represents the target. Pull-request review comments, formal reviews,
// and issue comments use the same target-level inbox behavior.
export function classifyTarget(
  target: GitHubTarget,
  username: string,
  config: AttentionConfig,
  options: ClassificationOptions = {},
): AttentionItem | null {
  const allComments = uniqueComments(target);
  const accountWide =
    targetIsOwned(target, username) ||
    participated(allComments, username, config);
  const relevant = accountWide || targetIsWatched(target);
  const reasons: AttentionReason[] = [];
  if (relevant) {
    const floor = commentFloor(target, options, accountWide);
    const comment = commentReason(target, username, config, floor);
    if (comment !== null) reasons.push(comment);
    const review = reviewReason(target, username, config, floor);
    if (review !== null) reasons.push(review);
  }
  const opened = openedReason(target, username, config, options.watchedSince);
  if (opened !== null) reasons.push(opened);
  return reasons.length === 0 ? null : attentionItem(target, reasons);
}
