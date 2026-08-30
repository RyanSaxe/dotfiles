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
    version: 1,
    lastAttemptAt: null,
    lastSuccessfulSyncAt: null,
    lastError: null,
    consecutiveFailures: 0,
    retryAfter: null,
    rateLimit: null,
    items: emptyRecord<AttentionItem>(),
    acknowledged: emptyRecord<string>(),
    notified: emptyRecord<string>(),
    ci: emptyRecord<CiMemory>(),
    githubSync: {
      processedThrough: null,
      lastFullReconciliationAt: null,
    },
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
  if (!isRecord(value) || value["version"] !== 1) {
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

export interface ReconciledState {
  state: ObserverState;
  pendingNotifications: AttentionItem[];
}

export function reconcileAttention(
  previous: ObserverState,
  items: AttentionItem[],
  ci: Record<string, CiMemory>,
): ReconciledState {
  const currentItems: Record<string, AttentionItem> = Object.fromEntries(
    items.map((item) => [item.id, item]),
  );
  const currentIds = new Set(Object.keys(currentItems));
  const acknowledged = Object.fromEntries(
    Object.entries(previous.acknowledged).filter(([id]) => currentIds.has(id)),
  );
  const notified = Object.fromEntries(
    Object.entries(previous.notified).filter(([id]) => currentIds.has(id)),
  );
  const pendingNotifications = items.filter(
    (item) =>
      acknowledged[item.id] === undefined && notified[item.id] === undefined,
  );
  return {
    state: {
      ...previous,
      items: currentItems,
      acknowledged,
      notified,
      ci,
    },
    pendingNotifications,
  };
}

function attentionTargetKey(item: AttentionItem): string {
  return `${item.targetKind}:${item.repository}#${item.number}`;
}

// Incremental fetches return only targets whose remote activity may have
// changed. Remove old items for those targets, retain the rest, and let the
// existing classifier output replace the removed items. A full pass keeps the
// old replacement behavior so closed targets and stale CI memory disappear.
export function reconcileGithubAttention(
  previous: ObserverState,
  items: AttentionItem[],
  ci: Record<string, CiMemory>,
  refreshedTargetKeys: readonly string[],
  fullReconciliation: boolean,
): ReconciledState {
  if (fullReconciliation) return reconcileAttention(previous, items, ci);
  const refreshed = new Set(refreshedTargetKeys);
  const retained = Object.values(previous.items).filter(
    (item) => !refreshed.has(attentionTargetKey(item)),
  );
  return reconcileAttention(previous, [...retained, ...items], {
    ...previous.ci,
    ...ci,
  });
}

// A baseline records the existing inbox without sending a phone notification
// for old activity. Activity stamped at or after the baseline start remains
// pending, so a target changing while the baseline is fetched is not hidden.
export function suppressBaselineNotifications(
  reconciled: ReconciledState,
  baselineAt: string,
): ReconciledState {
  const baseline = Date.parse(baselineAt);
  if (!Number.isFinite(baseline)) {
    throw new Error(`baseline timestamp is not a date: ${baselineAt}`);
  }
  const notified = { ...reconciled.state.notified };
  const pendingNotifications = reconciled.pendingNotifications.filter(
    (item) => {
      const createdAt = Date.parse(item.createdAt);
      if (Number.isFinite(createdAt) && createdAt < baseline) {
        notified[item.id] = baselineAt;
        return false;
      }
      return true;
    },
  );
  return {
    state: { ...reconciled.state, notified },
    pendingNotifications,
  };
}

export function acknowledgeItem(
  state: ObserverState,
  id: string,
  now = new Date().toISOString(),
): ObserverState {
  if (state.items[id] === undefined) {
    throw new Error(`attention item not found or no longer active: ${id}`);
  }
  return { ...state, acknowledged: { ...state.acknowledged, [id]: now } };
}

export function markNotified(
  state: ObserverState,
  ids: string[],
  now = new Date().toISOString(),
): ObserverState {
  const notified = { ...state.notified };
  for (const id of ids) notified[id] = now;
  return { ...state, notified };
}
