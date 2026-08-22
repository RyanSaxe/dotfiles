import { appendFile, mkdir } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

import { loadAttentionConfig } from "./config.js";
import { applyCiTransition } from "./ci.js";
import { fetchGithubSnapshot } from "./github.js";
import { sendNtfy, ntfyEndpoint } from "./ntfy.js";
import {
  acknowledgeItem,
  acquireRefreshLock,
  ATTENTION_STATE_DIR,
  loadObserverState,
  markFailure,
  markNotified,
  markSuccess,
  reconcileAttention,
  retryAfterForRateLimit,
  retryIsActive,
  saveObserverState,
} from "./state.js";
import type { AttentionItem, ObserverState } from "./types.js";
import { classifyOpened, classifyTarget } from "./classify.js";

const LOG_PATH = `${ATTENTION_STATE_DIR}/observer.log`;

async function logLine(message: string): Promise<void> {
  await mkdir(ATTENTION_STATE_DIR, { recursive: true });
  await appendFile(LOG_PATH, `${new Date().toISOString()} ${message}\n`);
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

function itemSort(a: AttentionItem, b: AttentionItem): number {
  if (a.priority !== b.priority) return a.priority === "high" ? -1 : 1;
  return b.createdAt.localeCompare(a.createdAt);
}

function itemLine(item: AttentionItem, acknowledged: boolean): string {
  const marker = acknowledged ? "✓" : "•";
  const actor = item.actor?.login ?? "GitHub";
  return `${marker} ${item.repository}#${item.number} [${item.kind}] ${actor}: ${item.summary} — ${item.url}`;
}

function notificationBody(
  items: AttentionItem[],
  previousSync: string | null,
): string {
  const prefix =
    previousSync === null
      ? "Initial GitHub attention sync"
      : `GitHub attention since ${previousSync}`;
  return [
    prefix,
    ...items.sort(itemSort).map((item) => itemLine(item, false)),
  ].join("\n");
}

function activeItems(state: ObserverState): AttentionItem[] {
  return Object.values(state.items).sort(itemSort);
}

function parseRefreshOptions(args: string[]): {
  force: boolean;
  notify: boolean;
} {
  return {
    force: args.includes("--force"),
    notify: !args.includes("--no-notify"),
  };
}

async function refresh(args: string[]): Promise<void> {
  const { force, notify } = parseRefreshOptions(args);
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
    const snapshot = await fetchGithubSnapshot(config.watch);
    const items: AttentionItem[] = [];
    const ci: ObserverState["ci"] = {};

    // The first poll that sees a repository records the moment, and only
    // things opened after it are ever reported. That is what keeps adding a
    // repository quiet instead of dumping years of open work into the inbox.
    const watchedSince: Record<string, string> = {
      ...(state.watchedSince ?? {}),
    };
    for (const repository of config.watch) {
      watchedSince[repository] ??= now;
    }

    for (const target of snapshot.targets) {
      const opened = classifyOpened(
        target,
        snapshot.username,
        config,
        watchedSince[target.repository],
      );
      if (opened !== null) items.push(opened);
      items.push(...classifyTarget(target, snapshot.username, config));
      if (target.kind !== "pull_request") continue;
      const ciTransition = applyCiTransition(
        target,
        state.ci[`${target.repository}#${target.number}`],
        snapshot.username,
        config,
      );
      ci[`${target.repository}#${target.number}`] = ciTransition.memory;
      if (ciTransition.item !== null) items.push(ciTransition.item);
    }

    const reconciled = reconcileAttention(state, items, ci);
    state = markSuccess(
      { ...reconciled.state, username: snapshot.username, watchedSince },
      snapshot.rateLimit,
      now,
    );
    const rateLimitRetry =
      snapshot.rateLimit === null
        ? null
        : retryAfterForRateLimit(snapshot.rateLimit, Date.parse(now));
    if (rateLimitRetry !== null) {
      state = { ...state, retryAfter: rateLimitRetry };
    }
    await saveObserverState(state);

    const endpoint = ntfyEndpoint();
    if (
      notify &&
      endpoint !== null &&
      reconciled.pendingNotifications.length > 0
    ) {
      // A failure here must not look like a GitHub failure. The items are
      // already stored and still correct; only their delivery failed, so it
      // is logged and recorded separately rather than backing off the poll.
      try {
        await sendNtfy(
          {
            title: `${reconciled.pendingNotifications.length} GitHub item${reconciled.pendingNotifications.length === 1 ? "" : "s"} need you`,
            body: notificationBody(
              reconciled.pendingNotifications,
              previousSync,
            ),
            priority: reconciled.pendingNotifications.some(
              (item) => item.priority === "high",
            )
              ? "high"
              : "default",
            tags: ["github", "review"],
          },
          endpoint,
        );
        state = markNotified(
          state,
          reconciled.pendingNotifications.map((item) => item.id),
          now,
        );
        state = { ...state, lastNotifyError: null };
      } catch (error) {
        // Left un-notified on purpose: the next poll retries delivery.
        const message = errorMessage(error);
        state = { ...state, lastNotifyError: message };
        await logLine(`notify failed: ${message}`);
      }
      await saveObserverState(state);
    }

    const gap =
      previousSync === null
        ? "initial"
        : `${Math.max(0, Date.parse(now) - Date.parse(previousSync))}ms since last success`;
    await logLine(
      `refresh ok: ${snapshot.targets.filter((t) => t.kind === "pull_request").length} PRs, ${snapshot.targets.filter((t) => t.kind === "issue").length} issues, ${items.length} active items, ${reconciled.pendingNotifications.length} pending notifications, ${snapshot.requestDurationMs}ms request, ${gap}${rateLimitRetry === null ? "" : `, rate pressure until ${rateLimitRetry}`}`,
    );
    console.log(
      `attention refresh: ${items.length} active item${items.length === 1 ? "" : "s"}; ${reconciled.pendingNotifications.length} notification${reconciled.pendingNotifications.length === 1 ? "" : "s"} pending`,
    );
    if (rateLimitRetry !== null) {
      console.log(`rate pressure: backing off until ${rateLimitRetry}`);
    }
    if (
      notify &&
      endpoint === null &&
      reconciled.pendingNotifications.length > 0
    ) {
      console.log("phone notification skipped: ntfy channel is not configured");
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
  const pending = items.filter(
    (item) => state.acknowledged[item.id] === undefined,
  );
  console.log(`state: ${ATTENTION_STATE_DIR}/state.json`);
  console.log(`last success: ${state.lastSuccessfulSyncAt ?? "never"}`);
  console.log(`last attempt: ${state.lastAttemptAt ?? "never"}`);
  console.log(`last error: ${state.lastError ?? "none"}`);
  console.log(`last notify error: ${state.lastNotifyError ?? "none"}`);
  console.log(`retry after: ${state.retryAfter ?? "none"}`);
  console.log(`active items: ${items.length}`);
  console.log(`unacknowledged: ${pending.length}`);
  console.log(
    `ntfy: ${ntfyEndpoint() === null ? "not configured" : "configured"}`,
  );
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
    console.log(itemLine(item, state.acknowledged[item.id] !== undefined));
  }
  if (Object.keys(state.items).length === 0)
    console.log("no active attention items");
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
  refresh [--force] [--no-notify]  fetch account-wide GitHub attention
  status                           show observer state and rate limit
  list [--json]                    show active attention items
  ack <item-id>                    acknowledge one item locally`);
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
