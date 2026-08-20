import { execFile } from "node:child_process";
import { homedir } from "node:os";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";

import { loadReviewSnapshot } from "./attention/review.js";
import {
  acknowledgeItem,
  loadObserverState,
  saveObserverState,
} from "./attention/state.js";
import type { AttentionItem } from "./attention/types.js";
import {
  runDashboard,
  type DashboardData,
  type DashboardItem,
  type DashboardSurface,
} from "./dashboard.js";
import { fmtElapsed } from "./cells.js";

const run = promisify(execFile);

function clean(text: string): string {
  return text.replace(/\s+/g, " ").trim();
}

function shortRepository(repository: string): string {
  const slash = repository.lastIndexOf("/");
  return slash >= 0 ? repository.slice(slash + 1) : repository;
}

function age(createdAt: string): string {
  const created = Date.parse(createdAt);
  if (!Number.isFinite(created)) return "?";
  return fmtElapsed(Math.max(0, (Date.now() - created) / 1000));
}

function kindLabel(item: AttentionItem): string {
  switch (item.kind) {
    case "ci":
      return "CI";
    case "review_comment":
      return "Review";
    case "conversation":
      return "Comment";
    case "review_request":
      return "Request";
  }
}

function ciLabel(
  state: NonNullable<AttentionItem["context"]>["ciState"],
): string | null {
  return state === "UNKNOWN" ? null : state.toLowerCase();
}

function reviewDetails(item: AttentionItem): string[] {
  const context = item.context;
  if (context === undefined) return [];

  const details: string[] = [];
  if (context.author !== null) {
    details.push(`PR author  @${context.author.login}`);
  }
  const ci = ciLabel(context.ciState);
  if (ci !== null) details.push(`CI         ${ci}`);
  if (context.body !== "") {
    details.push("");
    details.push(context.body);
  }
  return details;
}

export function reviewItem(
  item: AttentionItem,
  acknowledged: boolean,
): DashboardItem {
  const isCi = item.kind === "ci";
  const actor = item.actor?.login ?? "GitHub";
  return {
    id: item.id,
    project: shortRepository(item.repository),
    reference: `#${item.number}`,
    kind: kindLabel(item),
    state: acknowledged ? "seen" : isCi ? "CI red" : "needs you",
    time: age(item.createdAt),
    title: clean(item.title),
    preview: `${actor}: ${clean(item.summary)}`,
    details: reviewDetails(item),
    url: item.url,
    tone: isCi ? "error" : "waiting",
    acknowledged,
  };
}

export function reviewDashboardData(): DashboardData {
  const snapshot = loadReviewSnapshot();
  const items = snapshot.items.map((item) =>
    reviewItem(item, snapshot.acknowledged.has(item.id)),
  );
  const seen = items.filter((item) => item.acknowledged).length;
  const open = items.length - seen;
  return {
    surface: "reviews",
    items,
    status: `${open} open · ${seen} seen`,
    emptyMessage: "Review inbox is clear",
    // Refresh failures belong in `attention status`; keeping them out of the
    // selected review preview preserves the useful PR context.
    error: null,
  };
}

export function taskDashboardData(): DashboardData {
  return {
    surface: "tasks",
    items: [],
    status: "source pending",
    emptyMessage: "Tasks are waiting for Obsidian integration",
    error: null,
  };
}

async function openUrl(url: string): Promise<void> {
  const opener = process.platform === "darwin" ? "open" : "xdg-open";
  await run(opener, [url]);
}

export async function openReviewItem(itemIndex: number): Promise<boolean> {
  const snapshot = loadReviewSnapshot();
  const item = snapshot.unacknowledged[itemIndex];
  if (item === undefined) return false;
  await openUrl(item.url);
  return true;
}

async function acknowledgeReview(item: DashboardItem): Promise<void> {
  const state = await loadObserverState();
  if (state.items[item.id] === undefined) return;
  await saveObserverState(acknowledgeItem(state, item.id));
}

async function refreshReviews(): Promise<DashboardData> {
  // The observer owns the network lifecycle. The dashboard only requests an
  // explicit no-notify refresh and then re-reads the durable local snapshot.
  await run(join(homedir(), ".local", "bin", "attention"), [
    "refresh",
    "--no-notify",
  ]);
  return reviewDashboardData();
}

export async function main(
  surface: DashboardSurface = "reviews",
): Promise<void> {
  const isReviews = surface === "reviews";
  await runDashboard(isReviews ? reviewDashboardData() : taskDashboardData(), {
    refresh: isReviews ? refreshReviews : async () => taskDashboardData(),
    open: async (item) => {
      if (item.url !== null) await openUrl(item.url);
    },
    acknowledge: isReviews
      ? acknowledgeReview
      : async () => {
          throw new Error("task elements are not available yet");
        },
  });
}

const thisFile = fileURLToPath(import.meta.url);
if (process.argv[1] !== undefined && resolve(process.argv[1]) === thisFile) {
  const surface = process.argv[2] ?? "reviews";
  if (surface !== "reviews" && surface !== "tasks") {
    console.error("usage: review-dashboard reviews|tasks");
    process.exitCode = 1;
  } else {
    main(surface).catch((error: unknown) => {
      console.error(
        `dashboard: ${error instanceof Error ? error.message : String(error)}`,
      );
      process.exitCode = 1;
    });
  }
}
