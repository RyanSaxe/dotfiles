import { appendFile, mkdir } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { resolve } from "node:path";

import { loadAttentionConfig } from "./config.js";
import { applyCiTransition } from "./ci.js";
import { attentionItem, classifyTarget } from "./classify.js";
import { fetchGithubSync } from "./github.js";
import {
  acknowledgeItem,
  acquireRefreshLock,
  ATTENTION_STATE_DIR,
  commitGithubSync,
  loadObserverState,
  markFailure,
  markSuccess,
  reconcileGithubAttention,
  retryAfterForRateLimit,
  retryIsActive,
  saveObserverState,
  shouldRunFullReconciliation,
  unacknowledgedItems,
} from "./state.js";
import type { AttentionItem, AttentionReason, ObserverState } from "./types.js";

const LOG_PATH = `${ATTENTION_STATE_DIR}/observer.log`;

async function logLine(message: string): Promise<void> {
  await mkdir(ATTENTION_STATE_DIR, { recursive: true });
  await appendFile(LOG_PATH, `${new Date().toISOString()} ${message}\n`);
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
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

function itemLine(item: AttentionItem, acknowledged: boolean): string {
  const marker = acknowledged ? "✓" : "•";
  const actor =
    item.reasons.find((reason) => reason.actor !== null)?.actor?.login ??
    "GitHub";
  const reasons = item.reasons.map((reason) => reason.summary).join(" | ");
  return `${marker} ${item.repository}#${item.number} ${actor}: ${reasons} — ${item.url}`;
}

function activeItems(state: ObserverState): AttentionItem[] {
  return Object.values(state.items).sort(itemSort);
}

function parseRefreshOptions(args: string[]): {
  force: boolean;
  full: boolean;
} {
  return {
    force: args.includes("--force"),
    full: args.includes("--full"),
  };
}

function watchStarts(
  configured: readonly string[],
  previous: Record<string, string> | undefined,
  now: string,
): Record<string, string> {
  return Object.fromEntries(
    configured.map((repository) => [repository, previous?.[repository] ?? now]),
  );
}

async function refresh(args: string[]): Promise<void> {
  const { force, full } = parseRefreshOptions(args);
  const lock = await acquireRefreshLock();
  if (lock === null) {
    console.log("attention refresh already running");
    return;
  }

  let state = await loadObserverState();
  const previousSync = state.lastSuccessfulSyncAt;
  const now = new Date().toISOString();
  try {
    if (!force && retryIsActive(state)) {
      console.log(`attention refresh backed off until ${state.retryAfter}`);
      return;
    }

    state = { ...state, lastAttemptAt: now };
    await saveObserverState(state);
    const config = loadAttentionConfig();
    const initialBaseline = state.baselineAt === null;
    const baselineAt = state.baselineAt ?? now;
    const watchedSince = watchStarts(config.watch, state.watchedSince, now);
    const fullReconciliation =
      full || shouldRunFullReconciliation(state, Date.parse(now));
    const sync = await fetchGithubSync({
      watch: config.watch,
      since: state.githubSync?.processedThrough ?? null,
      fullReconciliation,
      startedAt: now,
    });
    const snapshot = sync.snapshot;
    const items: AttentionItem[] = [];
    const ci: ObserverState["ci"] = {};

    for (const target of snapshot.targets) {
      const classified = classifyTarget(target, snapshot.username, config, {
        baselineAt,
        watchedSince: watchedSince[target.repository],
      });
      const reasons = [...(classified?.reasons ?? [])];
      if (target.kind === "pull_request") {
        const ciKey = `${target.repository}#${target.number}`;
        const ciTransition = applyCiTransition(
          target,
          state.ci[ciKey],
          snapshot.username,
          config,
          baselineAt,
        );
        ci[ciKey] = ciTransition.memory;
        if (ciTransition.reason !== null) reasons.push(ciTransition.reason);
      }
      if (reasons.length > 0) items.push(attentionItem(target, reasons));
    }

    state = reconcileGithubAttention(
      state,
      items,
      ci,
      sync.refreshedTargetKeys,
      sync.fullReconciliation,
    );
    state = commitGithubSync(
      markSuccess(
        {
          ...state,
          username: snapshot.username,
          baselineAt,
          watchedSince,
        },
        snapshot.rateLimit,
        now,
      ),
      sync.processedThrough,
      sync.fullReconciliation,
    );
    const rateLimitRetry =
      snapshot.rateLimit === null
        ? null
        : retryAfterForRateLimit(snapshot.rateLimit, Date.parse(now));
    if (rateLimitRetry !== null) {
      state = { ...state, retryAfter: rateLimitRetry };
    }
    await saveObserverState(state);

    const active = activeItems(state);
    const pending = unacknowledgedItems(state);
    const gap =
      previousSync === null
        ? "initial"
        : `${Math.max(0, Date.parse(now) - Date.parse(previousSync))}ms since last success`;
    await logLine(
      `refresh ok: ${snapshot.targets.filter((t) => t.kind === "pull_request").length} PRs, ${snapshot.targets.filter((t) => t.kind === "issue").length} issues, ${items.length} items this pass, ${active.length} stored, ${pending.length} unacknowledged, ${snapshot.requestDurationMs}ms request, ${gap}${initialBaseline ? ", baseline established" : ""}${rateLimitRetry === null ? "" : `, rate pressure until ${rateLimitRetry}`}`,
    );
    console.log(
      `attention refresh: ${active.length} active item${active.length === 1 ? "" : "s"}; ${pending.length} unacknowledged`,
    );
    if (rateLimitRetry !== null) {
      console.log(`rate pressure: backing off until ${rateLimitRetry}`);
    }
  } catch (error) {
    const message = errorMessage(error);
    state = markFailure(state, message, now);
    await saveObserverState(state);
    await logLine(`refresh failed: ${message}`);
    throw error;
  } finally {
    await lock.release();
  }
}

async function status(): Promise<void> {
  const state = await loadObserverState();
  const items = activeItems(state);
  const pending = unacknowledgedItems(state);
  console.log(`state: ${ATTENTION_STATE_DIR}/state.json`);
  console.log(`last success: ${state.lastSuccessfulSyncAt ?? "never"}`);
  console.log(`last attempt: ${state.lastAttemptAt ?? "never"}`);
  console.log(`last error: ${state.lastError ?? "none"}`);
  console.log(`baseline: ${state.baselineAt ?? "not established"}`);
  console.log(
    `GitHub processed through: ${state.githubSync?.processedThrough ?? "never"}`,
  );
  console.log(
    `last full reconciliation: ${state.githubSync?.lastFullReconciliationAt ?? "never"}`,
  );
  console.log(`retry after: ${state.retryAfter ?? "none"}`);
  console.log(`active items: ${items.length}`);
  console.log(`unacknowledged: ${pending.length}`);
  if (state.rateLimit !== null) {
    console.log(
      `rate limit: ${state.rateLimit.remaining} remaining, cost ${state.rateLimit.cost}, reset ${state.rateLimit.resetAt}`,
    );
  }
}

async function list(args: string[]): Promise<void> {
  const state = await loadObserverState();
  if (args.includes("--json")) {
    console.log(
      JSON.stringify(
        { items: activeItems(state), acknowledged: state.acknowledged },
        null,
        2,
      ),
    );
    return;
  }
  for (const item of activeItems(state)) {
    console.log(
      itemLine(item, state.acknowledged[item.id] === item.activityKey),
    );
  }
  if (Object.keys(state.items).length === 0) {
    console.log("no active attention items");
  }
}

async function acknowledge(args: string[]): Promise<void> {
  const id = args[0];
  if (id === undefined || id === "") {
    throw new Error("usage: attention ack <item-id>");
  }
  const state = await loadObserverState();
  await saveObserverState(acknowledgeItem(state, id));
  console.log(`acknowledged ${id}`);
}

function usage(): void {
  console.log(`usage: attention <command>

commands:
  refresh [--force] [--full]  fetch account-wide GitHub attention
  status                     show observer state and rate limit
  list [--json]              show active attention items
  ack <item-id>              acknowledge one item locally`);
}

export async function main(args = process.argv.slice(2)): Promise<void> {
  const [command, ...rest] = args;
  switch (command) {
    case "refresh":
      await refresh(rest);
      return;
    case "status":
      await status();
      return;
    case "list":
      await list(rest);
      return;
    case "ack":
      await acknowledge(rest);
      return;
    default:
      usage();
  }
}

const thisFile = fileURLToPath(import.meta.url);
if (process.argv[1] !== undefined && resolve(process.argv[1]) === thisFile) {
  main().catch((error: unknown) => {
    console.error(`attention: ${errorMessage(error)}`);
    process.exitCode = 1;
  });
}
