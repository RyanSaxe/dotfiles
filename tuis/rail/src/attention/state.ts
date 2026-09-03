import {
  mkdir,
  open,
  readFile,
  rename,
  unlink,
  writeFile,
} from "node:fs/promises";
import { homedir } from "node:os";
import { dirname, join } from "node:path";

import type {
  AttentionItem,
  CiMemory,
  GithubSyncCheckpoint,
  ObserverState,
  RateLimit,
} from "./types.js";

export const ATTENTION_STATE_VERSION = 2;
export const ATTENTION_STATE_DIR = join(
  process.env["XDG_STATE_HOME"] ?? join(homedir(), ".local", "state"),
  "dotfiles",
  "attention",
);
export const ATTENTION_STATE_PATH = join(ATTENTION_STATE_DIR, "state.json");
export const ATTENTION_LOCK_PATH = join(ATTENTION_STATE_DIR, "refresh.lock");
export const FULL_RECONCILIATION_INTERVAL_MS = 6 * 60 * 60 * 1000;

function emptyRecord<T>(): Record<string, T> {
  return {};
}

export function emptyObserverState(): ObserverState {
  return {
    version: ATTENTION_STATE_VERSION,
    lastAttemptAt: null,
    lastSuccessfulSyncAt: null,
    lastError: null,
    consecutiveFailures: 0,
    retryAfter: null,
    rateLimit: null,
    items: emptyRecord<AttentionItem>(),
    acknowledged: emptyRecord<string>(),
    ci: emptyRecord<CiMemory>(),
    baselineAt: null,
    githubSync: {
      processedThrough: null,
      lastFullReconciliationAt: null,
    },
    watchedSince: {},
  };
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function errorCode(error: unknown): string | null {
  if (!isRecord(error)) return null;
  const code = error["code"];
  return typeof code === "string" ? code : null;
}

function parseState(value: unknown, path: string): ObserverState {
  if (!isRecord(value)) {
    throw new Error(
      `attention state ${path}: unsupported or corrupt state file`,
    );
  }
  // The attention schema intentionally has no migration path. A new observer
  // starts from a clean baseline instead of carrying old per-comment rows into
  // the target-level inbox.
  if (value["version"] !== ATTENTION_STATE_VERSION) {
    return emptyObserverState();
  }
  if (
    !isRecord(value["items"]) ||
    !isRecord(value["acknowledged"]) ||
    !isRecord(value["ci"])
  ) {
    throw new Error(
      `attention state ${path}: unsupported or corrupt state file`,
    );
  }
  return value as unknown as ObserverState;
}

export async function loadObserverState(
  path = ATTENTION_STATE_PATH,
): Promise<ObserverState> {
  try {
    const content = await readFile(path, "utf8");
    return parseState(JSON.parse(content) as unknown, path);
  } catch (error) {
    if (errorCode(error) === "ENOENT") return emptyObserverState();
    if (error instanceof SyntaxError) {
      throw new Error(`attention state ${path}: invalid JSON`);
    }
    throw error;
  }
}

export async function saveObserverState(
  state: ObserverState,
  path = ATTENTION_STATE_PATH,
): Promise<void> {
  const temporaryPath = `${path}.${process.pid}.tmp`;
  await mkdir(dirname(path), { recursive: true });
  try {
    await writeFile(temporaryPath, `${JSON.stringify(state, null, 2)}\n`, {
      encoding: "utf8",
      mode: 0o600,
    });
    await rename(temporaryPath, path);
  } catch (error) {
    await unlink(temporaryPath).catch(() => {});
    throw error;
  }
}

export interface RefreshLock {
  release(): Promise<void>;
}

function processIsAlive(pid: number): boolean {
  if (!Number.isInteger(pid) || pid <= 0) return false;
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

export async function acquireRefreshLock(
  path = ATTENTION_LOCK_PATH,
): Promise<RefreshLock | null> {
  await mkdir(dirname(path), { recursive: true });
  const lockContents = `${process.pid}\n`;

  for (let attempt = 0; attempt < 2; attempt += 1) {
    try {
      const handle = await open(path, "wx");
      await handle.writeFile(lockContents, "utf8");
      await handle.close();
      return {
        release: async () => {
          await unlink(path).catch(() => {});
        },
      };
    } catch (error) {
      if (errorCode(error) !== "EEXIST") throw error;
      try {
        const pid = Number.parseInt(await readFile(path, "utf8"), 10);
        if (processIsAlive(pid)) return null;
      } catch {
        // A partially-written or stale lock is safe to reclaim below.
      }
      await unlink(path).catch(() => {});
    }
  }
  return null;
}

export function retryIsActive(state: ObserverState, now = Date.now()): boolean {
  if (state.retryAfter === null) return false;
  const retryAt = Date.parse(state.retryAfter);
  return Number.isFinite(retryAt) && retryAt > now;
}

export function retryAfterForFailure(
  consecutiveFailures: number,
  now = Date.now(),
): string {
  const delaySeconds = Math.min(
    3600,
    300 * 2 ** Math.min(Math.max(consecutiveFailures - 1, 0), 4),
  );
  return new Date(now + delaySeconds * 1000).toISOString();
}

export function retryAfterForRateLimit(
  rateLimit: RateLimit,
  now = Date.now(),
): string | null {
  const resetAt = Date.parse(rateLimit.resetAt);
  const pressureThreshold = Math.max(100, rateLimit.cost * 10);
  if (
    !Number.isFinite(resetAt) ||
    resetAt <= now ||
    rateLimit.remaining > pressureThreshold
  ) {
    return null;
  }
  return new Date(resetAt).toISOString();
}

function githubSyncCheckpoint(state: ObserverState): GithubSyncCheckpoint {
  return (
    state.githubSync ?? {
      processedThrough: null,
      lastFullReconciliationAt: null,
    }
  );
}

export function shouldRunFullReconciliation(
  state: ObserverState,
  now = Date.now(),
): boolean {
  const checkpoint = githubSyncCheckpoint(state);
  if (checkpoint.processedThrough === null) return true;
  if (checkpoint.lastFullReconciliationAt === null) return true;
  const lastFull = Date.parse(checkpoint.lastFullReconciliationAt);
  return (
    !Number.isFinite(lastFull) ||
    now - lastFull >= FULL_RECONCILIATION_INTERVAL_MS
  );
}

export function commitGithubSync(
  state: ObserverState,
  processedThrough: string,
  fullReconciliation: boolean,
): ObserverState {
  const previous = githubSyncCheckpoint(state);
  return {
    ...state,
    githubSync: {
      processedThrough,
      lastFullReconciliationAt: fullReconciliation
        ? processedThrough
        : previous.lastFullReconciliationAt,
    },
  };
}

export function markFailure(
  state: ObserverState,
  error: string,
  now = new Date().toISOString(),
): ObserverState {
  const consecutiveFailures = state.consecutiveFailures + 1;
  return {
    ...state,
    lastAttemptAt: now,
    lastError: error,
    consecutiveFailures,
    retryAfter: retryAfterForFailure(consecutiveFailures, Date.parse(now)),
  };
}

export function markSuccess(
  state: ObserverState,
  rateLimit: RateLimit | null,
  now = new Date().toISOString(),
): ObserverState {
  return {
    ...state,
    lastAttemptAt: now,
    lastSuccessfulSyncAt: now,
    lastError: null,
    consecutiveFailures: 0,
    retryAfter: null,
    rateLimit,
  };
}

function activityIds(activityKey: string): Set<string> {
  return new Set(activityKey.split("|").filter((id) => id !== ""));
}

export function activityAcknowledgesItem(
  activityKey: string | undefined,
  item: AttentionItem,
): boolean {
  if (activityKey === undefined) return false;
  const acknowledged = activityIds(activityKey);
  return item.reasons.every((reason) => acknowledged.has(reason.id));
}

function isAcknowledged(
  acknowledged: Record<string, string>,
  item: AttentionItem,
): boolean {
  return activityAcknowledgesItem(acknowledged[item.id], item);
}

export function unacknowledgedItems(state: ObserverState): AttentionItem[] {
  return Object.values(state.items).filter(
    (item) => !isAcknowledged(state.acknowledged, item),
  );
}

// Items are target-level records. An acknowledgement survives a refresh when
// every current reason was already part of the dismissed activity revision.
export function reconcileAttention(
  previous: ObserverState,
  items: AttentionItem[],
  ci: Record<string, CiMemory>,
): ObserverState {
  const currentItems: Record<string, AttentionItem> = Object.fromEntries(
    items.map((item) => [item.id, item]),
  );
  const acknowledged = Object.fromEntries(
    Object.entries(previous.acknowledged).filter(
      ([id, activityKey]) =>
        currentItems[id] !== undefined &&
        activityAcknowledgesItem(activityKey, currentItems[id]),
    ),
  );
  return {
    ...previous,
    items: currentItems,
    acknowledged,
    ci,
  };
}

// Incremental fetches return only targets whose remote activity may have
// changed. Remove old items for those targets, retain the rest, and let the
// classifier replace the refreshed targets. A full pass also removes closed
// targets and stale CI memory.
export function reconcileGithubAttention(
  previous: ObserverState,
  items: AttentionItem[],
  ci: Record<string, CiMemory>,
  refreshedTargetKeys: readonly string[],
  fullReconciliation: boolean,
): ObserverState {
  if (fullReconciliation) return reconcileAttention(previous, items, ci);
  const refreshed = new Set(refreshedTargetKeys);
  const retained = Object.values(previous.items).filter(
    (item) => !refreshed.has(item.id),
  );
  return reconcileAttention(previous, [...retained, ...items], {
    ...previous.ci,
    ...ci,
  });
}

export function acknowledgeItem(
  state: ObserverState,
  id: string,
): ObserverState {
  const item = state.items[id];
  if (item === undefined) {
    throw new Error(`attention item not found or no longer active: ${id}`);
  }
  return {
    ...state,
    acknowledged: { ...state.acknowledged, [id]: item.activityKey },
  };
}
