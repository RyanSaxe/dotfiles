import { normalizeLogin, type AttentionConfig } from "./config.js";
import type { AttentionItem, CiMemory, PullRequestSnapshot } from "./types.js";

const RED_STATES = new Set(["FAILURE", "ERROR"]);

export function ciIsRed(state: PullRequestSnapshot["ciState"]): boolean {
  return RED_STATES.has(state);
}

function ownsPullRequest(pr: PullRequestSnapshot, username: string): boolean {
  return (
    pr.author !== null &&
    normalizeLogin(pr.author.login) === normalizeLogin(username)
  );
}

export interface CiTransition {
  memory: CiMemory;
  item: AttentionItem | null;
}

export function applyCiTransition(
  pr: PullRequestSnapshot,
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

  if (!config.ownPrCi || !ownsPullRequest(pr, username) || !newlyRed) {
    return { memory, item: null };
  }

  return {
    memory,
    item: {
      id: `ci:${pr.repository}#${pr.number}:${pr.headSha || "unknown"}:${redEpoch}`,
      kind: "ci",
      repository: pr.repository,
      number: pr.number,
      title: pr.title,
      url: pr.url,
      summary: `Owned PR CI is ${pr.ciState.toLowerCase()}`,
      actor: null,
      createdAt: pr.updatedAt,
      priority: "high",
    },
  };
}
