import { execFile, execFileSync } from "node:child_process";
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
  type MetaSpan,
} from "./dashboard.js";
import { fmtElapsed } from "./cells.js";
import { openPullRequestWorkspace } from "./workspace.js";
import {
  cleanupReviewWorktree,
  focusReviewWorktree,
  listReviewWorktrees,
  openAssistedReview,
  worktreeDiff,
  type ReviewWorktree,
} from "./worktrees.js";

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

// Markdown reaches the panel as pre-coloured lines. bat is a syntax
// highlighter rather than a renderer — the `##` stays visible — but it is
// already installed, already themed by the generated tmTheme, and needs no
// markdown renderer of our own. Anything it cannot do falls back to plain
// paragraphs rather than failing the frame.
export type MarkdownRenderer = (markdown: string) => string[];

export function batMarkdown(width: number): MarkdownRenderer {
  return (markdown) => {
    const source = markdown.trim();
    if (source === "") return [];
    try {
      return execFileSync(
        "bat",
        [
          "--language=md",
          "--color=always",
          "--paging=never",
          "--style=plain",
          `--terminal-width=${Math.max(20, width)}`,
          "--wrap=character",
        ],
        {
          input: source,
          encoding: "utf8",
          timeout: 5_000,
          // execFileSync inherits stderr by default. Anything bat says would
          // land on the terminal mid-frame and scroll it, taking the header
          // with it — the frame owns this screen.
          stdio: ["pipe", "pipe", "pipe"],
        },
      )
        .replace(/\n$/, "")
        .split("\n");
    } catch {
      return paragraphs(source);
    }
  };
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
// A PR is sized by its diff; an issue by its labels. Both answer "what kind
// of thing is this" at a glance, which is what the column is for.
function metadataFor(item: AttentionItem): MetaSpan[] {
  const context = item.context;
  if (context === undefined) return [];
  if (item.targetKind === "issue") {
    const labels = (context.labels ?? []).slice(0, 2).join(" ");
    return labels === "" ? [] : [{ text: labels, tone: "muted" }];
  }
  // State written before diff stats existed carries none; an empty cell is
  // honest, "+undefined" is not.
  const added = context.additions ?? 0;
  const removed = context.deletions ?? 0;
  const files = context.changedFiles ?? 0;
  if (added === 0 && removed === 0 && files === 0) return [];
  return [
    { text: `+${added}`, tone: "add" },
    { text: " ", tone: "muted" },
    { text: `-${removed}`, tone: "delete" },
    { text: " ", tone: "muted" },
    { text: `${files}f`, tone: "change" },
  ];
}

function toneFor(item: AttentionItem): DashboardTone {
  if (item.kind === "ci") return "ci";
  return item.targetKind === "issue" ? "issue" : "pull_request";
}

function previewFor(
  item: AttentionItem,
  target: string,
  viewerOwnsTarget: boolean,
  render: MarkdownRenderer,
): DashboardPreview {
  const context = item.context;
  const author = context?.author?.login ?? null;
  const trailer: string[] = [clean(item.title)];
  if (author !== null && !viewerOwnsTarget) {
    trailer.push(`opened by @${author}`);
  }

  // The description always follows the trigger. You opened this because
  // something happened; you still need to know what the PR or issue is.
  const description = context?.body ? render(context.body) : [];

  if (item.kind === "ci") {
    return {
      headline: `CI failed on ${target}`,
      bullets: context?.failingChecks ?? [],
      body: description,
      context: trailer,
    };
  }

  if (item.kind === "review_request") {
    return {
      headline: `Review requested on ${target}`,
      bullets: [],
      body: description,
      context: trailer,
    };
  }

  const actor = item.actor?.login;
  const comment = render(item.summary);
  return {
    headline: `${actor ? `@${actor}` : "Someone"} commented on ${target}`,
    bullets: [],
    // The comment first, then the description it was made against.
    body: description.length > 0 ? [...comment, "", ...description] : comment,
    context: trailer,
  };
}

export function reviewItem(
  item: AttentionItem,
  viewer: string | null,
  render: MarkdownRenderer = paragraphs,
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
    metadata: metadataFor(item),
    time: age(item.createdAt),
    title: clean(item.title),
    url: item.url,
    tone: toneFor(item),
    preview: previewFor(item, target, viewerOwnsTarget, render),
  };
}

export function reviewDashboardData(): DashboardData {
  const snapshot = loadReviewSnapshot();
  // Acknowledged items leave the table outright. A permanently dimmed row
  // is a to-do you cannot finish; the locked semantics say an acknowledged
  // item stays suppressed until a genuinely new external event, and a new
  // event arrives with a new id, so it comes back on its own.
  // Rendered once here, not per frame: the panel redraws on every keypress
  // and shelling out to bat that often would make navigation crawl.
  const render = batMarkdown((process.stdout.columns ?? 100) - 6);
  const items = snapshot.unacknowledged.map((item) =>
    reviewItem(item, snapshot.username, render),
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

interface PullRequestFacts {
  title: string;
  additions: number;
  deletions: number;
  changedFiles: number;
  url: string | null;
}

// The observer already knows this pull request if it is in the inbox. Reading
// its cache keeps the Worktrees view free of network calls; a workspace whose
// pull request is not an attention item simply shows less.
function factsFor(
  worktree: ReviewWorktree,
  items: readonly AttentionItem[],
): PullRequestFacts {
  const match = items.find(
    (item) =>
      item.repository === worktree.repository &&
      item.number === worktree.number,
  );
  return {
    title: match === undefined ? "" : clean(match.title),
    additions: match?.context?.additions ?? 0,
    deletions: match?.context?.deletions ?? 0,
    changedFiles: match?.context?.changedFiles ?? 0,
    url: match?.url ?? null,
  };
}

function worktreeItem(
  worktree: ReviewWorktree,
  facts: PullRequestFacts,
  diff: readonly string[],
): DashboardItem {
  const target = `${shortRepository(worktree.repository)}#${worktree.number}`;
  const context: string[] = [];
  if (facts.title !== "") context.push(facts.title);
  context.push(`branch    ${worktree.branch}`);
  context.push(`worktree  ${worktree.path}`);
  context.push(`session   ${worktree.session.trim()}`);
  return {
    id: worktree.path,
    repository: worktree.repository,
    reference: `#${worktree.number}`,
    from: worktree.attached ? "open" : "closed",
    author: worktree.dirty ? "uncommitted" : "clean",
    // Reused as "dim this cell": a clean worktree is the boring case.
    authorIsViewer: !worktree.dirty,
    reason: facts.title === "" ? worktree.branch : facts.title,
    metadata:
      facts.additions === 0 && facts.deletions === 0
        ? []
        : [
            { text: `+${facts.additions}`, tone: "add" },
            { text: " ", tone: "muted" },
            { text: `-${facts.deletions}`, tone: "delete" },
            { text: " ", tone: "muted" },
            { text: `${facts.changedFiles}f`, tone: "change" },
          ],
    time: worktree.ageSecs === 0 ? "" : fmtElapsed(worktree.ageSecs),
    title: worktree.branch,
    url: facts.url,
    // A workspace is not attention. Open and clean is the healthy case and
    // reads green; uncommitted work is the only thing worth a second look.
    tone: worktree.dirty
      ? "pull_request"
      : worktree.attached
        ? "clean"
        : "neutral",
    preview: {
      headline: `${target} · ${worktree.branch}`,
      bullets: [],
      // The diff, not a description of the workspace. This worktree exists to
      // be read; the row already said everything else.
      body: [...diff],
      context: worktree.dirty ? ["uncommitted changes in this worktree"] : [],
    },
  };
}

export async function worktreeDashboardData(): Promise<DashboardData> {
  const worktrees = await listReviewWorktrees();
  const cached = loadReviewSnapshot().items;
  const width = (process.stdout.columns ?? 100) - 6;
  const diffs = await Promise.all(
    worktrees.map(async (worktree) => worktreeDiff(worktree, width)),
  );
  const open = worktrees.filter((worktree) => worktree.attached).length;
  return {
    surface: "reviews",
    items: worktrees.map((worktree, index) =>
      worktreeItem(worktree, factsFor(worktree, cached), diffs[index] ?? []),
    ),
    status:
      worktrees.length === 0
        ? "no review workspaces"
        : `${worktrees.length} workspace${worktrees.length === 1 ? "" : "s"} · ${open} open`,
    emptyMessage: "No pull request is checked out locally",
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

// `gh pr diff | delta`, with the arguments passed as positional parameters
// so nothing from GitHub is ever interpolated into a shell string. Delta's
// colours pass through untouched; the view only measures widths.
async function reviewDiff(item: DashboardItem): Promise<string[]> {
  if (item.tone === "issue") {
    return ["An issue has no diff."];
  }
  const number = item.reference.replace(/^#/, "");
  const width = String(Math.max(40, (process.stdout.columns ?? 100) - 2));
  try {
    const { stdout } = await run(
      "sh",
      [
        "-c",
        'gh pr diff "$1" --repo "$2" | delta --paging=never --width "$3"',
        "sh",
        number,
        item.repository,
        width,
      ],
      { maxBuffer: 32 * 1024 * 1024, timeout: 30_000 },
    );
    const lines = stdout.replace(/\n$/, "").split("\n");
    return lines.length === 1 && lines[0] === ""
      ? ["This pull request has no changes."]
      : lines;
  } catch (error) {
    return [
      `Could not load the diff: ${error instanceof Error ? error.message.split("\n")[0] : String(error)}`,
    ];
  }
}

// Enter on a pull request resolves the repository, asks workmux for a
// worktree and a session, and stands aside so the client lands in it.
// Issues have no worktree, so they open where they are readable: the browser.
async function openReviewWorkspace(item: DashboardItem): Promise<boolean> {
  if (item.tone === "issue") {
    if (item.url !== null) await openUrl(item.url);
    return false;
  }
  const number = Number(item.reference.replace(/^#/, ""));
  if (!Number.isFinite(number)) {
    if (item.url !== null) await openUrl(item.url);
    return false;
  }
  await openPullRequestWorkspace(item.repository, number);
  // The item moves rather than vanishes: it is a workspace now, listed under
  // Worktrees. A genuinely new external event arrives with a new id and
  // brings it back to the inbox on its own.
  await acknowledgeReview(item);
  return true;
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
    open: openReviewWorkspace,
    browser: async (item) => {
      if (item.url !== null) await openUrl(item.url);
    },
    diff: reviewDiff,
    worktrees: isReviews ? worktreeDashboardData : undefined,
    focus: async (item) => {
      const worktree = (await listReviewWorktrees()).find(
        (candidate) => candidate.path === item.id,
      );
      if (worktree !== undefined) await focusReviewWorktree(worktree);
    },
    // Assisted review never starts implicitly. It adds a second window to the
    // pull request's own session, so the human review stays where it was and
    // the two are a window apart.
    assist: async (item) => {
      const number = Number(item.reference.replace(/^#/, ""));
      if (!Number.isFinite(number) || item.tone === "issue") return;
      await openPullRequestWorkspace(item.repository, number);
      const worktree = (await listReviewWorktrees()).find(
        (candidate) =>
          candidate.repository === item.repository &&
          candidate.number === number,
      );
      if (worktree !== undefined) await openAssistedReview(worktree);
    },
    cleanup: async (item) => {
      const worktree = (await listReviewWorktrees()).find(
        (candidate) => candidate.path === item.id,
      );
      if (worktree === undefined) return "that workspace is already gone";
      const result = await cleanupReviewWorktree(worktree);
      return result.ok ? null : result.reason;
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
