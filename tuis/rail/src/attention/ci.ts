import { normalizeLogin, type AttentionConfig } from "./config.js";
import { reviewContext } from "./context.js";
import type {
  AttentionItem,
  CiMemory,
  CiTransition,
  PullRequestTarget,
} from "./types.js";

const RED_STATES = new Set(["FAILURE", "ERROR"]);

export function ciIsRed(state: PullRequestTarget["ciState"]): boolean {
  return RED_STATES.has(state);
}

function ownsPullRequest(pr: PullRequestTarget, username: string): boolean {
  return (
    pr.author !== null &&
    normalizeLogin(pr.author.login) === normalizeLogin(username)
  );
}

export function applyCiTransition(
  pr: PullRequestTarget,
  previous: CiMemory | undefined,
  username: string,
  config: AttentionConfig,
): CiTransition {
  const red = ciIsRed(pr.ciState);
  const headChanged = previous !== undefined && previous.headSha !== pr.headSha;
  const newlyRed =
    red && (previous === undefined || !previous.red || headChanged);
  const redEpoch = (previous?.redEpoch ?? 0) + (newlyRed ? 1 : 0);
  const memory: CiMemory = {
    state: pr.ciState,
    headSha: pr.headSha,
    red,
    redEpoch,
  };

  if (!config.ownPrCi || !ownsPullRequest(pr, username) || !red) {
    return { memory, item: null, newlyRed };
  }

  return {
    memory,
    item: {
      id: `ci:${pr.repository}#${pr.number}:${pr.headSha || "unknown"}:${redEpoch}`,
      kind: "ci",
      targetKind: "pull_request",
      repository: pr.repository,
      number: pr.number,
      title: pr.title,
      url: pr.url,
      // One item per PR, naming the checks that failed — never one item
      // per check, and never the ones that passed.
      summary:
        pr.failingChecks.length > 0
          ? `CI failed: ${pr.failingChecks.join(", ")}`
          : `CI is ${pr.ciState.toLowerCase()}`,
      actor: null,
      createdAt: pr.updatedAt,
      priority: "high",
      context: reviewContext(pr),
    },
    newlyRed,
  };
}
