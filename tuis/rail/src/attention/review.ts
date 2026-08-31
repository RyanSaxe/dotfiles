import { readFileSync, statSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

import type { AttentionItem, AttentionReason, ObserverState } from "./types.js";
import { activityAcknowledgesItem, ATTENTION_STATE_VERSION } from "./state.js";

const STATE_PATH = join(
  process.env["XDG_STATE_HOME"] ?? join(homedir(), ".local", "state"),
  "dotfiles",
  "attention",
  "state.json",
);

export interface ReviewSnapshot {
  revision: number;
  username: string | null;
  lastSuccessfulSyncAt: string | null;
  lastError: string | null;
  items: AttentionItem[];
  unacknowledged: AttentionItem[];
  acknowledged: ReadonlySet<string>;
}

let cachedPath = "";
let cachedMtime = -1;
let cachedSnapshot = emptyReviewSnapshot(0);

function emptyReviewSnapshot(revision: number): ReviewSnapshot {
  return {
    revision,
    username: null,
    lastSuccessfulSyncAt: null,
    lastError: null,
    items: [],
    unacknowledged: [],
    acknowledged: new Set<string>(),
  };
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isAttentionReason(value: unknown): value is AttentionReason {
  return (
    isRecord(value) &&
    typeof value["id"] === "string" &&
    (value["kind"] === "comment" ||
      value["kind"] === "ci" ||
      value["kind"] === "opened") &&
    typeof value["summary"] === "string" &&
    typeof value["createdAt"] === "string" &&
    (value["priority"] === "normal" || value["priority"] === "high")
  );
}

function isAttentionItem(value: unknown): value is AttentionItem {
  return (
    isRecord(value) &&
    typeof value["id"] === "string" &&
    (value["targetKind"] === "pull_request" ||
      value["targetKind"] === "issue") &&
    typeof value["repository"] === "string" &&
    typeof value["number"] === "number" &&
    typeof value["title"] === "string" &&
    typeof value["url"] === "string" &&
    typeof value["activityKey"] === "string" &&
    Array.isArray(value["reasons"]) &&
    value["reasons"].length > 0 &&
    value["reasons"].every(isAttentionReason)
  );
}

function primaryReason(item: AttentionItem): AttentionReason {
  const reason = item.reasons[0];
  if (reason === undefined)
    throw new Error(`attention item ${item.id} has no reason`);
  return reason;
}

function itemSort(a: AttentionItem, b: AttentionItem): number {
  const aReason = primaryReason(a);
  const bReason = primaryReason(b);
  if (aReason.priority !== bReason.priority) {
    return aReason.priority === "high" ? -1 : 1;
  }
  return bReason.createdAt.localeCompare(aReason.createdAt);
}

function parseState(value: unknown): ObserverState {
  if (
    !isRecord(value) ||
    value["version"] !== ATTENTION_STATE_VERSION ||
    !isRecord(value["items"]) ||
    !isRecord(value["acknowledged"])
  ) {
    throw new Error("invalid attention state");
  }
  return value as unknown as ObserverState;
}

function readSnapshot(path: string, revision: number): ReviewSnapshot {
  const raw = JSON.parse(readFileSync(path, "utf8")) as unknown;
  // The target-level schema starts clean. Do not render rows from the old
  // per-comment state while the observer is waiting for its first refresh.
  if (!isRecord(raw) || raw["version"] !== ATTENTION_STATE_VERSION) {
    return emptyReviewSnapshot(revision);
  }
  const state = parseState(raw);
  const items = Object.values(state.items)
    .filter(isAttentionItem)
    .sort(itemSort);
  const acknowledged = new Set(
    items
      .filter((item) =>
        activityAcknowledgesItem(state.acknowledged[item.id], item),
      )
      .map((item) => item.id),
  );
  return {
    revision,
    username: state.username ?? null,
    lastSuccessfulSyncAt: state.lastSuccessfulSyncAt,
    lastError: state.lastError,
    items,
    unacknowledged: items.filter((item) => !acknowledged.has(item.id)),
    acknowledged,
  };
}

export function loadReviewSnapshot(path = STATE_PATH): ReviewSnapshot {
  let mtime = 0;
  try {
    mtime = statSync(path).mtimeMs;
  } catch {
    if (cachedPath === path && cachedMtime === 0) return cachedSnapshot;
    cachedPath = path;
    cachedMtime = 0;
    cachedSnapshot = emptyReviewSnapshot(0);
    return cachedSnapshot;
  }
  if (cachedPath === path && cachedMtime === mtime) return cachedSnapshot;

  cachedPath = path;
  cachedMtime = mtime;
  try {
    cachedSnapshot = readSnapshot(path, mtime);
  } catch (error) {
    cachedSnapshot = {
      ...emptyReviewSnapshot(mtime),
      lastError: error instanceof Error ? error.message : String(error),
    };
  }
  return cachedSnapshot;
}
