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
  EMPTY_CELL,
  runDashboard,
  type DashboardData,
  type DashboardItem,
  type DashboardPreview,
  type DashboardSurface,
  type DashboardTone,
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

function sameLogin(a: string | null, b: string | null): boolean {
  if (a === null || b === null) return false;
  return (
    a.trim().replace(/^@/, "").toLowerCase() ===
    b.trim().replace(/^@/, "").toLowerCase()
  );
}

// GitHub bodies are markdown; the panel is not. Strip the syntax that
// renders as noise in a terminal rather than dumping it verbatim, which is
// what made the old preview unreadable.
function plainText(markdown: string): string {
  return markdown
    .replace(/```[\s\S]*?```/g, " ")
    .replace(/(^|\s)#{1,6}\s+/g, "$1")
    .replace(/!\[[^\]]*\]\([^)]*\)/g, "")
    .replace(/\[([^\]]+)\]\([^)]*\)/g, "$1")
    .replace(/[*_`>]/g, "")
    .replace(/\s+/g, " ")
    .trim();
}

// Nothing shown in the panel is truncated. The panel scrolls, so a cap only
// buys a description that stops mid-sentence. Paragraphs survive as separate
// entries so the renderer can space them.
function paragraphs(text: string): string[] {
  return text
    .split(/\n\s*\n/)
    .map((paragraph) => plainText(paragraph))
    .filter((paragraph) => paragraph !== "");
}

// What this row needs from you, stated as one phrase. The actor is NOT in
// here — it has its own column, and saying it twice is what made the old
// table repeat itself.
function reasonFor(item: AttentionItem, viewerOwnsTarget: boolean): string {
  const object = item.targetKind === "issue" ? "issue" : "PR";
  switch (item.kind) {
    case "ci": {
      const checks = item.context?.failingChecks ?? [];
      return checks.length > 0
        ? `CI failed — ${checks.join(", ")}`
        : "CI failed";
    }
    case "review_request":
      return "Review requested";
    case "review_comment":
      return "Commented on a review thread";
    case "opened":
      return item.targetKind === "issue" ? "New issue opened" : "New PR opened";
    case "conversation":
      return viewerOwnsTarget
        ? `Commented on your ${object}`
        : `Commented on this ${object}`;
  }
}

// Hue follows the object, never the severity — except CI, which is the one
// genuinely critical state.
function toneFor(item: AttentionItem): DashboardTone {
  if (item.kind === "ci") return "ci";
  return item.targetKind === "issue" ? "issue" : "pull_request";
}

function previewFor(
  item: AttentionItem,
  target: string,
  viewerOwnsTarget: boolean,
): DashboardPreview {
  const context = item.context;
  const author = context?.author?.login ?? null;
  const trailer: string[] = [clean(item.title)];
  if (author !== null && !viewerOwnsTarget)
    trailer.push(`opened by @${author}`);

  if (item.kind === "ci") {
    return {
      headline: `CI failed on ${target}`,
      bullets: context?.failingChecks ?? [],
      body: context?.body ? paragraphs(context.body) : [],
      context: trailer,
    };
  }

  if (item.kind === "review_request") {
    return {
      headline: `Review requested on ${target}`,
      bullets: [],
      body: context?.body ? paragraphs(context.body) : [],
      context: trailer,
    };
  }

  const actor = item.actor?.login;
  return {
    headline: `${actor ? `@${actor}` : "Someone"} commented on ${target}`,
    bullets: [],
    body: paragraphs(item.summary),
    context: trailer,
  };
}

export function reviewItem(
  item: AttentionItem,
  viewer: string | null,
): DashboardItem {
  const target = `${shortRepository(item.repository)}#${item.number}`;
  const author = item.context?.author?.login ?? null;
  const viewerOwnsTarget = sameLogin(author, viewer);
  return {
    id: item.id,
    repository: item.repository,
    reference: `#${item.number}`,
    // GitHub sends no actor for CI or a review request; Author carries
    // those, so the cell stays honestly empty rather than inventing one.
    from: item.actor === null ? EMPTY_CELL : `@${item.actor.login}`,
    author: author === null ? EMPTY_CELL : `@${author}`,
    authorIsViewer: viewerOwnsTarget,
    reason: reasonFor(item, viewerOwnsTarget),
    time: age(item.createdAt),
    title: clean(item.title),
    url: item.url,
    tone: toneFor(item),
    preview: previewFor(item, target, viewerOwnsTarget),
  };
}

export function reviewDashboardData(): DashboardData {
  const snapshot = loadReviewSnapshot();
  // Acknowledged items leave the table outright. A permanently dimmed row
  // is a to-do you cannot finish; the locked semantics say an acknowledged
  // item stays suppressed until a genuinely new external event, and a new
  // event arrives with a new id, so it comes back on its own.
  const items = snapshot.unacknowledged.map((item) =>
    reviewItem(item, snapshot.username),
  );
  return {
    surface: "reviews",
    items,
    status: items.length === 1 ? "1 needs you" : `${items.length} need you`,
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
    // Enter will grow into the workspace path; browser is a peer action,
    // not a fallback, and deliberately does NOT clear the item — only a
    // reply, a reaction, or `x` does.
    open: async (item) => {
      if (item.url !== null) await openUrl(item.url);
    },
    browser: async (item) => {
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
