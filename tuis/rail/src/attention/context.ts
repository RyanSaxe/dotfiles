import type { PullRequestSnapshot, ReviewContext } from "./types.js";

const MAX_BODY_LENGTH = 800;

function compactBody(body: string): string {
  const compact = body.replace(/\s+/g, " ").trim();
  if (compact.length <= MAX_BODY_LENGTH) return compact;
  return `${compact.slice(0, MAX_BODY_LENGTH - 1).trimEnd()}…`;
}

export function reviewContext(pr: PullRequestSnapshot): ReviewContext {
  return {
    body: compactBody(pr.body),
    author: pr.author,
    ciState: pr.ciState,
  };
}
