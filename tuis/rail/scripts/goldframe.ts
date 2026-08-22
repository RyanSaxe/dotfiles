// Renders the gold-standard scene through the real renderer: the exact
// windows and agents pictured in the design page, covering every state
// (working / waiting / done), urgency sorting, and truncation. Pipe the
// output through ansi2png.py to judge cells against the design.
//
//   npx tsx scripts/goldframe.ts | uv run -q --script scripts/ansi2png.py gold.png

import type { RailData } from "../src/data.js";
import { assignHints } from "../src/hints.js";
import { renderRail } from "../src/render.js";
import { loadPalette } from "../src/theme.js";

const reviewItems = [
  {
    id: "review:1",
    kind: "review_comment" as const,
    targetKind: "pull_request" as const,
    repository: "RyanSaxe/dotfiles-v2",
    number: 90,
    title: "Review cockpit",
    url: "https://github.com/RyanSaxe/dotfiles-v2/pull/90",
    summary: "Please take another look at this change",
    actor: { login: "reviewer", kind: "user" as const },
    createdAt: "2026-08-19T16:00:00Z",
    priority: "normal" as const,
  },
  {
    id: "ci:2",
    kind: "ci" as const,
    targetKind: "pull_request" as const,
    repository: "RyanSaxe/buffergolf.nvim",
    number: 4,
    title: "Improve buffer flow",
    url: "https://github.com/RyanSaxe/buffergolf.nvim/pull/4",
    summary: "CI is red",
    actor: null,
    createdAt: "2026-08-19T15:30:00Z",
    priority: "high" as const,
  },
];

const configuredTab = process.env.RAIL_TAB;

const scene: RailData = {
  session: "dotfiles",
  activeTab:
    configuredTab === "reviews" || configuredTab === "review"
      ? "reviews"
      : configuredTab === "tasks"
        ? "tasks"
        : "agents",
  acked: new Set(process.env.RAIL_ACK ? [process.env.RAIL_ACK] : []),
  hints: new Map(),
  sprite: null,
  page: Number(process.env.RAIL_PAGE ?? 0),
  prefixHeld: Boolean(process.env.RAIL_PREFIX),
  windows: [
    { index: 1, name: "nvim", active: false, paneIds: ["%1"] },
    { index: 2, name: "zsh", active: true, paneIds: ["%2"] },
    { index: 3, name: "claude", active: false, paneIds: ["%3"] },
    { index: 4, name: "zsh", active: false, paneIds: ["%4"] },
  ],
  agents: [
    {
      session: "dotfiles",
      windowName: "claude",
      paneId: "%3",
      status: "working",
      title: "✳ building the agent rail",
      elapsedSecs: 6 * 60,
      updatedTs: 300,
      worktree: "dotfiles",
      branch: "main",
    },
    {
      session: "watchtower",
      windowName: "claude",
      paneId: "%9",
      status: "waiting",
      title: "apply migration? (y/n)",
      elapsedSecs: 12 * 60,
      updatedTs: 200,
      worktree: "fix-auth",
      branch: "fix-auth",
    },
    {
      session: "byor",
      windowName: "claude",
      paneId: "%11",
      status: "done",
      title: "✳ ingest pipeline green — 47 files touched in the end",
      elapsedSecs: 41 * 60,
      updatedTs: 100,
      worktree: "ingest",
      branch: "ingest",
    },
    {
      session: "byor",
      windowName: "codex",
      paneId: "%13",
      status: "working",
      title: "refactoring eval loader",
      elapsedSecs: 3 * 60,
      updatedTs: 250,
      worktree: "byor",
      branch: "evals",
    },
  ],
  review: {
    revision: 1,
    username: "ryansaxe",
    lastSuccessfulSyncAt: "2026-08-19T16:00:00Z",
    lastError: null,
    items: reviewItems,
    unacknowledged: reviewItems,
    acknowledged: new Set<string>(),
  },
};

scene.hints =
  assignHints(scene.agents, [scene.session], scene.acked).get(scene.session) ??
  new Map();

// Defaults mirror the shipped pane geometry (daemon.ts RAIL_WIDTH).
const width = Number(process.env.RAIL_WIDTH ?? 27);
const height = Number(process.env.RAIL_HEIGHT ?? 41);
process.stdout.write(
  renderRail(scene, loadPalette(), width, height).join("\n") + "\n",
);
