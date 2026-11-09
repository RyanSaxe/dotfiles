import { normalizeLogin, type AttentionConfig } from "./config.js";
import type {
  AttentionReason,
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
  baselineAt: string | null = null,
): CiTransition {
  const red = ciIsRed(pr.ciState);
  const headChanged = previous !== undefined && previous.headSha !== pr.headSha;
  const newlyRed =
    red && (previous === undefined || !previous.red || headChanged);
  const redEpoch = (previous?.redEpoch ?? 0) + (newlyRed ? 1 : 0);
  const isAfterBaseline =
    baselineAt === null || Date.parse(pr.updatedAt) >= Date.parse(baselineAt);
  const alerted =
    red && (previous?.alerted === true || (newlyRed && isAfterBaseline));
  const memory: CiMemory = {
    state: pr.ciState,
    headSha: pr.headSha,
    red,
    redEpoch,
    alerted,
  };

  if (!config.ownPrCi || !ownsPullRequest(pr, username) || !red) {
    return { memory, reason: null, newlyRed };
  }

  if (!alerted) return { memory, reason: null, newlyRed };

  return {
    memory,
    reason: {
      id: `ci:${pr.repository}#${pr.number}:${pr.headSha || "unknown"}:${redEpoch}`,
      kind: "ci",
      summary:
        pr.failingChecks.length > 0
          ? `CI failed: ${pr.failingChecks.join(", ")}`
          : `CI is ${pr.ciState.toLowerCase()}`,
      actor: null,
      createdAt: pr.updatedAt,
      priority: "high",
    },
    newlyRed,
  };
}
