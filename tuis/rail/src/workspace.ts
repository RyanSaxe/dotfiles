// Turning a review row into somewhere to actually read the code.
//
// The layers stay separate on purpose. This module resolves a GitHub
// `owner/name` to a clone on disk and then asks workmux for a worktree and a
// tmux session. It never creates a worktree or a session itself: workmux owns
// that lifecycle, including cleanup and resurrection, and a second creator
// would race it.

import { execFile } from "node:child_process";
import { existsSync, type Dirent } from "node:fs";
import { mkdir, readdir } from "node:fs/promises";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { promisify } from "node:util";

const run = promisify(execFile);

// git reads GIT_DIR, GIT_WORK_TREE and GIT_INDEX_FILE from the environment,
// and they override -C. Anything invoked from a hook — or from a tool that
// sets them — would otherwise resolve to whatever repository the caller was
// in rather than the one being asked about. Strip them for every git-touching
// process here; gh and workmux both shell out to git in turn.
const GIT_FREE_ENV: NodeJS.ProcessEnv = Object.fromEntries(
  Object.entries(process.env).filter(([key]) => !key.startsWith("GIT_")),
);

// Clones this tool makes land here. The existing roots are searched first, so
// a repository you already have is used where it is rather than cloned twice.
export const MANAGED_ROOT = join(homedir(), "repositories");

export const SEARCH_ROOTS = [
  join(homedir(), "work"),
  join(homedir(), "projects"),
  join(homedir(), "generic"),
  MANAGED_ROOT,
];

export interface ReviewWorkspace {
  repository: string;
  number: number;
  clone: string;
  worktree: string;
  session: string;
  cloned: boolean;
}

function normalize(repository: string): string {
  return repository
    .trim()
    .replace(/\.git$/, "")
    .toLowerCase();
}

// A remote can be either form; both name the same repository.
//   git@github.com:owner/name.git
//   https://github.com/owner/name
function remoteRepository(url: string): string | null {
  const match = /(?:[:/])([^/:]+\/[^/]+?)(?:\.git)?\s*$/.exec(url.trim());
  return match?.[1] ?? null;
}

async function remoteOf(directory: string): Promise<string | null> {
  try {
    const { stdout } = await run(
      "git",
      ["-C", directory, "remote", "get-url", "origin"],
      { env: GIT_FREE_ENV },
    );
    return remoteRepository(stdout);
  } catch {
    return null;
  }
}

// Walk for repositories rather than shelling out to `fd`.
//
// fd was the obvious choice and the wrong one: it is not installed
// everywhere — Debian names the binary fdfind — and its absence made this
// return nothing rather than fail, so every repository looked missing and
// would have been cloned a second time. CI caught it; a fresh machine would
// have too, silently.
//
// Depth is bounded and a repository is not descended into: checkouts live a
// few levels under a root, and the contents of one are never another.
const MAX_DEPTH = 4;
const SKIP = new Set(["node_modules", ".venv", "venv", "target", "vendor"]);

async function gitDirectories(roots: readonly string[]): Promise<string[]> {
  const found: string[] = [];

  const walk = async (directory: string, depth: number): Promise<void> => {
    if (depth > MAX_DEPTH) return;
    let entries: Dirent[];
    try {
      entries = await readdir(directory, { withFileTypes: true });
    } catch {
      return;
    }
    // A worktree's `.git` is a file, not a directory; both mark a checkout.
    if (entries.some((entry) => entry.name === ".git")) {
      found.push(directory);
      return;
    }
    await Promise.all(
      entries
        .filter(
          (entry) =>
            entry.isDirectory() &&
            !entry.name.startsWith(".") &&
            !SKIP.has(entry.name),
        )
        .map(async (entry) => walk(join(directory, entry.name), depth + 1)),
    );
  };

  await Promise.all(
    roots.filter((root) => existsSync(root)).map(async (root) => walk(root, 0)),
  );
  return found;
}

// Match on the remote, not the directory name. They diverge often enough to
// matter — dotfiles-v2 on disk is RyanSaxe/dotfiles on GitHub — and cloning a
// second copy of a repository you already have would be the worst outcome.
export async function findClone(
  repository: string,
  roots: readonly string[] = SEARCH_ROOTS,
): Promise<string | null> {
  const wanted = normalize(repository);
  const name = wanted.split("/")[1] ?? wanted;
  const candidates = await gitDirectories(roots);

  // Directory name usually matches, so check those first and avoid running
  // git against every repository on the machine.
  const likely = candidates.filter(
    (directory) => directory.split("/").pop()?.toLowerCase() === name,
  );
  for (const directory of [...likely, ...candidates]) {
    const remote = await remoteOf(directory);
    if (remote !== null && normalize(remote) === wanted) return directory;
  }
  return null;
}

export async function ensureClone(repository: string): Promise<{
  path: string;
  cloned: boolean;
}> {
  const existing = await findClone(repository);
  if (existing !== null) return { path: existing, cloned: false };

  const target = join(MANAGED_ROOT, repository);
  if (existsSync(target)) {
    throw new Error(
      `${target} already exists but is not a clone of ${repository}; move it aside or clone by hand`,
    );
  }
  await mkdir(dirname(target), { recursive: true });
  try {
    await run("gh", ["repo", "clone", repository, target], {
      timeout: 300_000,
      env: GIT_FREE_ENV,
    });
  } catch (error) {
    const detail =
      error instanceof Error ? error.message.split("\n")[0] : String(error);
    throw new Error(`could not clone ${repository}: ${detail}`);
  }
  return { path: target, cloned: true };
}

// The worktree directory is already namespaced by project, so the number
// alone identifies it. The tmux session is not namespaced by anything, so it
// carries the repository too — two projects can both have a PR #4.
export function workspaceHandle(
  repository: string,
  pullRequest: number,
): { name: string; target: string } {
  const project = repository.split("/")[1] ?? repository;
  // workmux slugifies the target it is given — `buffergolf.nvim-pr-4` becomes
  // `buffergolf-nvim-pr-4` as a tmux session. Slugify here too, so the name
  // recorded is the name tmux actually has.
  const slug = project
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
  return {
    name: `pr-${pullRequest}`,
    target: `${slug}-pr-${pullRequest}`,
  };
}

export function workmuxArguments(
  repository: string,
  pullRequest: number,
): string[] {
  const { name, target } = workspaceHandle(repository, pullRequest);
  return [
    "add",
    "--pr",
    String(pullRequest),
    // Session mode: one session per pull request, so an assisted-review
    // window can join it later without disturbing the human one.
    "--session",
    // Idempotent reuse. Opening a review twice focuses the workspace that is
    // already there rather than building a second one.
    "--open-if-exists",
    "--name",
    name,
    "--target-name",
    target,
    // The review layout is one pane running an editor. Without it the global
    // `agent: codex` would start a reviewer nobody asked for every time a
    // pull request is opened to be read.
    "--layout",
    "review",
  ];
}

// Where workmux puts a worktree, asked of git rather than assumed.
async function findWorktree(
  clone: string,
  name: string,
): Promise<string | null> {
  try {
    const { stdout } = await run("git", ["worktree", "list", "--porcelain"], {
      cwd: clone,
      env: GIT_FREE_ENV,
    });
    for (const line of stdout.split("\n")) {
      const path = /^worktree (.+)$/.exec(line.trim())?.[1];
      if (path !== undefined && path.endsWith(`/${name}`)) return path;
    }
  } catch {
    return null;
  }
  return null;
}

export interface OpenOptions {
  dryRun?: boolean;
}

export async function openPullRequestWorkspace(
  repository: string,
  pullRequest: number,
  options: OpenOptions = {},
): Promise<ReviewWorkspace> {
  const { path: clone, cloned } = await ensureClone(repository);
  const { name, target } = workspaceHandle(repository, pullRequest);
  const args = workmuxArguments(repository, pullRequest);
  if (options.dryRun === true) args.push("--dry-run");

  // workmux both prepares the workspace and moves the client to it. The
  // second half can fail on its own — switching clients from inside a popup
  // is exactly that case — and a non-zero exit then hides a workspace that
  // was created perfectly well. So a failure is only a failure if the
  // worktree is not there afterwards.
  let stdout = "";
  try {
    ({ stdout } = await run("workmux", args, {
      cwd: clone,
      timeout: 300_000,
      maxBuffer: 4 * 1024 * 1024,
      env: GIT_FREE_ENV,
    }));
  } catch (error) {
    const settled = await findWorktree(clone, name);
    if (settled === null) {
      const detail =
        error instanceof Error
          ? (error.message.split("\n")[0] ?? error.message)
          : String(error);
      throw new Error(
        `could not open a workspace for ${repository}#${pullRequest}: ${detail}`,
      );
    }
    return {
      repository,
      number: pullRequest,
      clone,
      worktree: settled,
      session: target,
      cloned,
    };
  }
  // Ask git where the worktree is rather than scraping it out of workmux's
  // output: that line is only printed by --dry-run, so a real run left the
  // path empty. `stdout` is still read for the dry-run case.
  const worktree =
    /^Worktree:\s*(.+)$/m.exec(stdout)?.[1]?.trim() ??
    (await findWorktree(clone, name)) ??
    "";

  return {
    repository,
    number: pullRequest,
    clone,
    worktree,
    session: target,
    cloned,
  };
}

export { run as runForTests, remoteRepository };
