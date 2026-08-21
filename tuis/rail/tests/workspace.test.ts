// Resolving a GitHub repository to somewhere on disk, and asking workmux for
// a worktree. Nothing here creates anything: the invocation is asserted as
// arguments, and the resolver is pointed at fixture directories.

import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, mkdirSync, realpathSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";

import {
  findClone,
  remoteRepository,
  workmuxArguments,
  workspaceHandle,
} from "../src/workspace.js";

test("a remote is recognised in either form", () => {
  assert.equal(
    remoteRepository("git@github.com:RyanSaxe/dotfiles.git"),
    "RyanSaxe/dotfiles",
  );
  assert.equal(
    remoteRepository("https://github.com/RyanSaxe/dotfiles"),
    "RyanSaxe/dotfiles",
  );
  assert.equal(
    remoteRepository("https://github.com/RyanSaxe/dotfiles.git\n"),
    "RyanSaxe/dotfiles",
  );
});

test("the worktree is named by number, the session also by repository", () => {
  // Worktrees are already namespaced by project on disk; tmux sessions are
  // not namespaced by anything, so two projects could both want "pr-4".
  const handle = workspaceHandle("someorg/infra", 4);
  assert.equal(handle.name, "pr-4");
  assert.equal(handle.target, "infra-pr-4");
});

test("the session name matches what workmux actually creates", () => {
  // workmux slugifies the target it is given: buffergolf.nvim-pr-4 becomes
  // the tmux session buffergolf-nvim-pr-4. Recording the unslugified name
  // would leave the Worktrees view looking for a session that never exists.
  assert.equal(
    workspaceHandle("RyanSaxe/buffergolf.nvim", 4).target,
    "buffergolf-nvim-pr-4",
  );
});

test("workmux is asked for a reusable session with no agent", () => {
  const args = workmuxArguments("someorg/infra", 4).join(" ");
  assert.match(args, /--pr 4/);
  // Session mode, so an assisted-review window can join it later.
  assert.match(args, /--session/);
  // Idempotent: opening a review twice focuses the existing workspace.
  assert.match(args, /--open-if-exists/);
  // The review layout is one editor pane. Without it the global agent
  // would start a reviewer nobody asked for.
  assert.match(args, /--layout review/);
  assert.ok(!args.includes("--agent"));
});

// git reads GIT_DIR, GIT_WORK_TREE and GIT_INDEX_FILE from the environment
// and they override -C. pre-commit sets them, so a fixture that did not scrub
// them re-initialised the real repository instead of the temporary one — and
// marked it bare. Strip every GIT_* variable, and then verify the repository
// git ended up in is the one this function just created.
const CLEAN_GIT_ENV: NodeJS.ProcessEnv = Object.fromEntries(
  Object.entries(process.env).filter(([key]) => !key.startsWith("GIT_")),
);

const git = (cwd: string, args: string[]): string =>
  execFileSync("git", args, { cwd, env: CLEAN_GIT_ENV, encoding: "utf8" });

const repoAt = (root: string, path: string, remote: string): string => {
  const directory = join(root, path);
  mkdirSync(directory, { recursive: true });
  git(directory, ["init", "-q"]);
  const toplevel = realpathSync(
    git(directory, ["rev-parse", "--show-toplevel"]).trim(),
  );
  assert.equal(
    toplevel,
    realpathSync(directory),
    "fixture escaped its temporary directory — refusing to touch a real repository",
  );
  git(directory, ["remote", "add", "origin", remote]);
  return directory;
};

test("a clone is matched by its remote, not its directory name", async () => {
  // These diverge often enough to matter: dotfiles-v2 on disk is
  // RyanSaxe/dotfiles on GitHub. Matching on the name would clone a second
  // copy of a repository already present.
  const root = mkdtempSync(join(tmpdir(), "rail-ws-"));
  const expected = repoAt(
    root,
    "misnamed-on-disk",
    "git@github.com:owner/actual.git",
  );
  repoAt(root, "actual", "git@github.com:someone-else/actual.git");
  assert.equal(await findClone("owner/actual", [root]), expected);
});

test("a repository that is not on disk resolves to nothing", async () => {
  const root = mkdtempSync(join(tmpdir(), "rail-ws-"));
  repoAt(root, "something", "git@github.com:owner/something.git");
  assert.equal(await findClone("owner/absent", [root]), null);
});

test("matching ignores case and a trailing .git", async () => {
  const root = mkdtempSync(join(tmpdir(), "rail-ws-"));
  const expected = repoAt(root, "thing", "https://github.com/Owner/Thing");
  assert.equal(await findClone("owner/thing.git", [root]), expected);
});

test("a root that does not exist is skipped rather than failing", async () => {
  assert.equal(await findClone("owner/thing", ["/nonexistent-root"]), null);
});
