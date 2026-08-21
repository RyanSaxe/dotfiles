import type { GitHubTarget, ReviewContext } from "./types.js";

// Bodies are stored whole. The preview scrolls, so there is nothing a cap
// buys except a description that stops mid-sentence. Paragraph breaks are
// kept too — collapsing them turns a structured description into one
// unreadable run.
function normalizeBody(body: string): string {
  return body
    .replace(/\r\n/g, "\n")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

export function reviewContext(target: GitHubTarget): ReviewContext {
  return {
    body: normalizeBody(target.body),
    author: target.author,
    ciState: target.kind === "pull_request" ? target.ciState : "UNKNOWN",
    failingChecks: target.kind === "pull_request" ? target.failingChecks : [],
  };
}
