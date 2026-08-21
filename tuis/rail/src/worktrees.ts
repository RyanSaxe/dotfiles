// The Worktrees side of the Reviews dashboard: pull requests you have already
// opened locally.
//
// Discovery is deterministic rather than registered. A review workspace is a
// `pr-<number>` worktree under workmux's worktree root, and its session name
// follows from the repository and that number — so there is no second registry
// to keep in step with workmux's own.

import { execFile } from "node:child_process";
import { existsSync } from "node:fs";
import { readdir } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";
import { promisify } from "node:util";

import { workspaceHandle } from "./workspace.js";

const run = promisify(execFile);

// git and anything that shells out to it must not inherit a caller's GIT_DIR.
const GIT_FREE_ENV: NodeJS.ProcessEnv = Object.fromEntries(
  Object.entries(process.env).filter(([key]) => !key.startsWith("GIT_")),
);

export const WORKTREE_ROOT = join(homedir(), "worktrees");

export interface ReviewWorktree {
  repository: string;
  project: string;
  number: number;
  branch: string;
  path: string;
  session: string;
  attached: boolean;
  dirty: boolean;
  // Seconds since the branch's last commit. Cheap, local, and a better
  // answer to "is this stale" than when the directory was made.
  ageSecs: number;
}

const REVIEW_WORKTREE = /^pr-(\d+)$/;

async function directories(path: string): Promise<string[]> {
  try {
    const entries = await readdir(path, { withFileTypes: true });
    return entries
      .filter((entry) => entry.isDirectory())
      .map((entry) => entry.name);
  } catch {
    return [];
  }
}

async function git(cwd: string, args: string[]): Promise<string> {
  try {
    const { stdout } = await run("git", args, { cwd, env: GIT_FREE_ENV });
    return stdout.trim();
  } catch {
    return "";
  }
}

// workmux decorates the session name it creates: the tmux session for
// `buffergolf-nvim-pr-3` is actually "\uf418 buffergolf-nvim-pr-3", with a
// nerd-font glyph and a space in front. Comparing names for equality would
// never match, so both sides are reduced to what identifies them.
function sessionKey(name: string): string {
  return name.replace(/^[^a-zA-Z0-9]+/, "").trim();
}

async function openSessions(): Promise<Map<string, string>> {
  try {
    const { stdout } = await run("tmux", [
      "list-sessions",
      "-F",
      "#{session_name}",
    ]);
    const sessions = new Map<string, string>();
    for (const line of stdout.split("\n")) {
      const name = line.trim();
      if (name !== "") sessions.set(sessionKey(name), name);
    }
    return sessions;
  } catch {
    // No server running is not an error: it means nothing is open.
    return new Map();
  }
}

function repositoryFrom(remote: string): string {
  const match = /(?:[:/])([^/:]+\/[^/]+?)(?:\.git)?\s*$/.exec(remote.trim());
  return match?.[1] ?? "";
}

export async function listReviewWorktrees(
  root = WORKTREE_ROOT,
): Promise<ReviewWorktree[]> {
  if (!existsSync(root)) return [];
  const sessions = await openSessions();
  const found: ReviewWorktree[] = [];

  for (const project of await directories(root)) {
    for (const entry of await directories(join(root, project))) {
      const match = REVIEW_WORKTREE.exec(entry);
      if (match === null) continue;
      const number = Number(match[1]);
      const path = join(root, project, entry);
      const repository = repositoryFrom(
        await git(path, ["remote", "get-url", "origin"]),
      );
      if (repository === "") continue;
      const committed = await git(path, ["log", "-1", "--format=%ct"]);
      const { target } = workspaceHandle(repository, number);
      // Record the name tmux actually has, so focusing a workspace does not
      // have to reconstruct the decoration.
      const live = sessions.get(target);
      found.push({
        repository,
        project,
        number,
        branch: await git(path, ["branch", "--show-current"]),
        path,
        session: live ?? target,
        attached: live !== undefined,
        dirty: (await git(path, ["status", "--porcelain"])) !== "",
        ageSecs: (() => {
          const at = Number(committed);
          return Number.isFinite(at) && at > 0
            ? Math.max(0, Date.now() / 1000 - at)
            : 0;
        })(),
      });
    }
  }

  return found.sort(
    (a, b) => a.repository.localeCompare(b.repository) || a.number - b.number,
  );
}

export async function focusReviewWorktree(
  worktree: ReviewWorktree,
): Promise<void> {
  // switch-client inside tmux, attach outside it. Either way the session is
  // workmux's; this only moves the client to it.
  const inside = process.env["TMUX"] !== undefined;
  await run("tmux", [
    inside ? "switch-client" : "attach-session",
    "-t",
    worktree.session,
  ]);
}

export interface CleanupRefusal {
  ok: false;
  reason: string;
}

export async function cleanupReviewWorktree(
  worktree: ReviewWorktree,
): Promise<{ ok: true } | CleanupRefusal> {
  // Uncommitted work is never discarded here. workmux refuses it too without
  // --force, which is deliberately not passed — but refusing early gives a
  // reason worth reading instead of a subprocess error.
  if (worktree.dirty) {
    return {
      ok: false,
      reason: `${worktree.path} has uncommitted changes; commit or discard them first`,
    };
  }
  try {
    // --keep-branch: the branch belongs to the pull request, not to this
    // workspace, and may be checked out somewhere you still care about.
    await run("workmux", ["remove", "--keep-branch", `pr-${worktree.number}`], {
      cwd: worktree.path,
      env: { ...GIT_FREE_ENV, WORKMUX_YES: "1" },
      timeout: 120_000,
    });
    return { ok: true };
  } catch (error) {
    const detail =
      error instanceof Error
        ? (error.message.split("\n")[0] ?? error.message)
        : String(error);
    return { ok: false, reason: detail };
  }
}

// The assisted-review window.
//
// workmux layouts describe panes, not windows, so a second window cannot come
// from one. tmux creates it directly — which is additive rather than a race:
// workmux still owns the session and the worktree, and removing either takes
// this window with it.
const ASSISTED_WINDOW = "codex";

async function windowNames(session: string): Promise<string[]> {
  try {
    const { stdout } = await run("tmux", [
      "list-windows",
      "-t",
      session,
      "-F",
      "#{window_name}",
    ]);
    return stdout
      .split("\n")
      .map((name) => name.trim())
      .filter((name) => name !== "");
  } catch {
    return [];
  }
}

export interface AssistedReview {
  session: string;
  created: boolean;
}

export async function openAssistedReview(
  worktree: ReviewWorktree,
): Promise<AssistedReview> {
  const existing = await windowNames(worktree.session);
  // Repeating the action focuses the reviewer that is already running rather
  // than starting a second one.
  if (existing.includes(ASSISTED_WINDOW)) {
    await run("tmux", [
      "select-window",
      "-t",
      `${worktree.session}:${ASSISTED_WINDOW}`,
    ]);
    return { session: worktree.session, created: false };
  }

  // Codex starts already knowing what it is for. The prompt asks it to make
  // the human review easier rather than to replace it: findings and where to
  // check them, not a verdict, and no changes to a worktree that exists to be
  // read.
  const prompt = [
    `You are helping review pull request #${worktree.number} of`,
    `${worktree.repository}, checked out here on branch ${worktree.branch}.`,
    "Read the diff against its base branch and report what a careful reviewer",
    "would want to know before reading it themselves: what the change is",
    "trying to do, anything incorrect or risky, and anything the description",
    "does not explain. Say where each point is, so it can be checked. Prefer a",
    "short list of things worth attention over a summary of everything.",
    "Do not modify files and do not post anything to GitHub — this worktree is",
    "for reading, and the review is submitted by a human.",
  ].join(" ");

  await run("tmux", [
    "new-window",
    "-t",
    worktree.session,
    "-n",
    ASSISTED_WINDOW,
    "-c",
    worktree.path,
    // Codex explicitly. The global workmux agent happens to be codex today,
    // but this path must not depend on that staying true.
    "codex",
    prompt,
  ]);
  return { session: worktree.session, created: true };
}
