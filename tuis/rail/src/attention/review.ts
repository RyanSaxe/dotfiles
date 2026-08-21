import { readFileSync, statSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

import type { AttentionItem, ObserverState } from "./types.js";

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

function isAttentionItem(value: unknown): value is AttentionItem {
  return (
    isRecord(value) &&
    typeof value["id"] === "string" &&
    typeof value["kind"] === "string" &&
    typeof value["repository"] === "string" &&
    typeof value["number"] === "number" &&
    typeof value["title"] === "string" &&
    typeof value["url"] === "string" &&
    typeof value["summary"] === "string" &&
    typeof value["createdAt"] === "string" &&
    (value["priority"] === "normal" || value["priority"] === "high")
  );
}

function itemSort(a: AttentionItem, b: AttentionItem): number {
  if (a.priority !== b.priority) return a.priority === "high" ? -1 : 1;
  return b.createdAt.localeCompare(a.createdAt);
}

function parseState(value: unknown): ObserverState {
  if (
    !isRecord(value) ||
    value["version"] !== 1 ||
    !isRecord(value["items"]) ||
    !isRecord(value["acknowledged"])
  ) {
    throw new Error("invalid attention state");
  }
  return value as unknown as ObserverState;
}

function readSnapshot(path: string, revision: number): ReviewSnapshot {
  const state = parseState(JSON.parse(readFileSync(path, "utf8")) as unknown);
  const items = Object.values(state.items)
    .filter(isAttentionItem)
    .sort(itemSort);
  const acknowledged = new Set(Object.keys(state.acknowledged));
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
