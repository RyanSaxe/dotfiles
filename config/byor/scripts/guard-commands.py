#!/usr/bin/env python3
"""Context-aware pre-command safety guard for BYOR.

Reads a candidate shell command on stdin and exits nonzero with a corrective
message when the command performs a high-blast-radius destructive action:
recursive force deletes outside scratch directories, repo-wide git discards,
forced removal of dirty worktrees or unmerged branches, or mutating git stash
operations while linked worktrees exist.
"""

from __future__ import annotations

import shlex
import subprocess
import sys
from pathlib import Path

# Explicit scratch roots allowed for automatic `rm -rf` cleanup (not creating temp files).
SCRATCH_ROOTS = (
    "/tmp",  # noqa: S108 -- path allowlist, not temp file creation
    "/private/tmp",
    "/var/folders",
    "/private/var/folders",
)
GLOB_CHARS = set("*?[]")
SHELL_SEPARATORS = {"&&", "||", ";", "|", "&", "\n", "(", ")"}
WRAPPER_COMMANDS = {"command", "builtin", "exec", "nohup", "time", "sudo"}
GIT_OPTIONS_WITH_ARG = {"-C", "-c", "--git-dir", "--work-tree", "--namespace", "--config-env"}
MIN_SUBCMD_TOKENS = 2


def split_segments(command: str) -> list[list[str]]:
    """Split a shell command into token lists for each simple command segment."""
    lexer = shlex.shlex(command, posix=True, punctuation_chars=";&|()\n")
    lexer.whitespace_split = False
    lexer.commenters = "#"
    segments: list[list[str]] = []
    current: list[str] = []
    try:
        tokens = list(lexer)
    except ValueError:
        # Unbalanced quotes: fall back to whitespace split so obvious patterns
        # still get checked instead of silently bypassing the guard.
        tokens = command.split()

    for token in tokens:
        if token in SHELL_SEPARATORS or set(token) <= set(";&|\n"):
            if current:
                segments.append(current)
                current = []
            continue
        current.append(token)
    if current:
        segments.append(current)
    return segments


def _skip_env_prefix(tokens: list[str], idx: int) -> int:
    while idx < len(tokens):
        arg = tokens[idx]
        if arg in {"-u", "-C", "-S"}:
            idx += 2
        elif arg.startswith("-") or ("=" in arg and arg.split("=", 1)[0].isidentifier()):
            idx += 1
        else:
            break
    return idx


def strip_prefixes(tokens: list[str]) -> list[str]:
    """Strip leading VAR=val assignments, `env` flags/assignments, and shell wrappers."""
    idx = 0
    while idx < len(tokens):
        tok = tokens[idx]
        if "=" in tok and not tok.startswith("-") and tok.split("=", 1)[0].isidentifier():
            idx += 1
            continue
        base = Path(tok).name
        if base in WRAPPER_COMMANDS:
            idx += 1
            while idx < len(tokens) and tokens[idx].startswith("-"):
                idx += 1
            continue
        if base == "env":
            idx = _skip_env_prefix(tokens, idx + 1)
            continue
        break
    return tokens[idx:]


def is_in_scratch(path: Path) -> bool:
    """Return True if resolved path is strictly inside a known scratch root."""
    resolved = str(path.resolve())
    return any(resolved == root or resolved.startswith(f"{root}/") for root in SCRATCH_ROOTS)


def is_safe_rm_target(raw: str) -> bool:
    """Allow recursive force delete only on explicit paths under scratch or agent-notes/."""
    has_bad_syntax = (
        not raw
        or any(ch in GLOB_CHARS for ch in raw)
        or "$" in raw
        or "`" in raw
        or raw.startswith("~")
        or ".." in Path(raw).parts
    )
    cleaned = raw.rstrip("/")
    if has_bad_syntax or not cleaned:
        return False

    if cleaned.startswith("/"):
        return any(cleaned.startswith(f"{root}/") and len(cleaned) > len(root) + 1 for root in SCRATCH_ROOTS)

    normalized = cleaned.removeprefix("./")
    return normalized.startswith("agent-notes/") and len(normalized) > len("agent-notes/")


def _parse_rm_args(tokens: list[str]) -> tuple[bool, bool, list[str]]:
    recursive = False
    force = False
    targets: list[str] = []
    after_double_dash = False

    for tok in tokens[1:]:
        if not after_double_dash and tok == "--":
            after_double_dash = True
        elif not after_double_dash and tok.startswith("--"):
            recursive = recursive or tok == "--recursive"
            force = force or tok == "--force"
        elif not after_double_dash and tok.startswith("-") and len(tok) > 1:
            flags = tok[1:]
            recursive = recursive or ("r" in flags or "R" in flags)
            force = force or ("f" in flags)
        else:
            targets.append(tok)
    return recursive, force, targets


def check_rm(tokens: list[str]) -> str | None:
    """Block `rm -rf` outside safe scratch and `agent-notes/` targets."""
    recursive, force, targets = _parse_rm_args(tokens)
    if not (recursive and force) or not targets:
        return None

    unsafe = [target for target in targets if not is_safe_rm_target(target)]
    if not unsafe:
        return None
    joined = ", ".join(unsafe)
    return (
        f"Blocked recursive force delete on {joined}. "
        "Automatic `rm -rf` is only allowed on explicit non-glob paths inside /tmp/, /var/folders/, or agent-notes/. "
        "Delete specific files without `-rf`, or ask the user first."
    )


def parse_git(tokens: list[str]) -> tuple[Path, str | None, list[str]]:
    """Return (effective_cwd, subcommand, subcommand_args) for a git invocation."""
    git_cwd = Path.cwd()
    idx = 1
    while idx < len(tokens):
        tok = tokens[idx]
        if tok == "-C" and idx + 1 < len(tokens):
            candidate = Path(tokens[idx + 1])
            git_cwd = candidate if candidate.is_absolute() else git_cwd / candidate
            idx += 2
            continue
        if tok.startswith("-C") and len(tok) > MIN_SUBCMD_TOKENS:
            candidate = Path(tok[2:])
            git_cwd = candidate if candidate.is_absolute() else git_cwd / candidate
            idx += 1
            continue
        if tok in GIT_OPTIONS_WITH_ARG and idx + 1 < len(tokens):
            idx += 2
            continue
        if tok.startswith("-"):
            idx += 1
            continue
        return git_cwd, tok, tokens[idx + 1 :]
    return git_cwd, None, []


def has_linked_worktrees(git_cwd: Path) -> bool:
    """Return True when the repo at git_cwd has at least one linked worktree."""
    result = subprocess.run(
        ["git", "-C", str(git_cwd), "rev-parse", "--git-common-dir"],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        return False
    common_dir = Path(result.stdout.strip())
    if not common_dir.is_absolute():
        common_dir = (git_cwd / common_dir).resolve()
    worktrees_dir = common_dir / "worktrees"
    if not worktrees_dir.is_dir():
        return False
    return any(worktrees_dir.iterdir())


def _parse_branch_delete_args(args: list[str]) -> tuple[bool, bool, list[str]]:
    forced = False
    delete_flag = False
    branches: list[str] = []
    after_dd = False
    for arg in args:
        if not after_dd and arg == "--":
            after_dd = True
        elif not after_dd and arg.startswith("--"):
            forced = forced or arg == "--force"
            delete_flag = delete_flag or arg == "--delete"
        elif not after_dd and arg.startswith("-") and len(arg) > 1:
            flags = arg[1:]
            forced = forced or ("D" in flags or "f" in flags)
            delete_flag = delete_flag or ("D" in flags or "d" in flags)
        else:
            branches.append(arg)
    return forced, delete_flag, branches


def check_git_branch(git_cwd: Path, args: list[str]) -> str | None:
    """Allow `git branch -d`; block `git branch -D` if any target branch is unmerged."""
    forced, delete_flag, branches = _parse_branch_delete_args(args)
    if not (forced and delete_flag) or not branches:
        return None

    unmerged: list[str] = []
    for branch in branches:
        merged = subprocess.run(
            ["git", "-C", str(git_cwd), "merge-base", "--is-ancestor", branch, "HEAD"],
            capture_output=True,
            check=False,
        )
        if merged.returncode != 0:
            unmerged.append(branch)

    if not unmerged:
        return None
    names = ", ".join(unmerged)
    return (
        f"Blocked `git branch -D` on unmerged branch(es): {names}. "
        "Use `git branch -d` for merged branches, or ask the user before force-deleting unmerged work."
    )


def _is_dirty_or_unreadable_worktree(git_cwd: Path, target: str) -> bool:
    target_path = Path(target)
    if not target_path.is_absolute():
        target_path = git_cwd / target_path
    if not target_path.exists():
        return False
    status = subprocess.run(
        ["git", "-C", str(target_path), "status", "--porcelain"],
        capture_output=True,
        text=True,
        check=False,
    )
    return status.returncode != 0 or status.stdout.strip() != ""


def check_git_worktree_remove(git_cwd: Path, args: list[str]) -> str | None:
    """Allow non-forced worktree removal; block `-f`/`--force` when the worktree is dirty or unknown."""
    forced = False
    targets: list[str] = []
    for arg in args[1:]:
        if arg in {"-f", "--force"} or (arg.startswith("-") and not arg.startswith("--") and "f" in arg[1:]):
            forced = True
        elif not arg.startswith("-"):
            targets.append(arg)
    if not forced:
        return None

    for target in targets:
        if _is_dirty_or_unreadable_worktree(git_cwd, target):
            return (
                f"Blocked forced worktree removal on dirty or unreadable worktree `{target}`. "
                "Run `git worktree remove` without `--force` after committing or cleaning, or ask the user first."
            )
    return None


def _check_git_discard(subcmd: str, args: list[str]) -> str | None:
    if subcmd == "reset" and "--hard" in args:
        return (
            "Blocked `git reset --hard` outside a scratch directory. "
            "It permanently discards uncommitted changes. Inspect `git status` and ask the user first."
        )

    if subcmd == "clean":
        has_force = any(
            arg == "--force" or (arg.startswith("-") and not arg.startswith("--") and "f" in arg[1:]) for arg in args
        )
        is_dry_run = any(
            arg == "--dry-run" or (arg.startswith("-") and not arg.startswith("--") and "n" in arg[1:]) for arg in args
        )
        if has_force and not is_dry_run:
            return (
                "Blocked `git clean -f` outside a scratch directory. "
                "Preview with `git clean -nd` first and ask the user before deleting untracked files."
            )

    if subcmd in {"checkout", "restore"} and any(arg in {".", "./", ":/"} for arg in args):
        return (
            f"Blocked repo-wide `git {subcmd}` on `.`. "
            "Target only the specific file(s) you intend to revert, or ask the user first."
        )
    return None


def check_git(tokens: list[str]) -> str | None:
    """Apply context-aware git safety checks."""
    git_cwd, subcmd, args = parse_git(tokens)
    if not subcmd:
        return None

    if subcmd == "stash":
        action = next((arg for arg in args if not arg.startswith("-")), "push")
        if action not in {"list", "show"} and has_linked_worktrees(git_cwd):
            return (
                "Blocked mutating `git stash` while linked worktrees exist. "
                "The stash stack is shared across worktrees and can clobber another session's work. "
                "Commit WIP to a branch instead, or use `git stash list` / `git stash show`."
            )
        return None
    if subcmd == "branch":
        return check_git_branch(git_cwd, args)
    if subcmd == "worktree" and args and args[0] == "remove":
        return check_git_worktree_remove(git_cwd, args)
    return None if is_in_scratch(git_cwd) else _check_git_discard(subcmd, args)


def check_ws(tokens: list[str]) -> str | None:
    """Allow `ws rm <name>`; block `ws rm -f` / `--force`."""
    if len(tokens) >= MIN_SUBCMD_TOKENS and tokens[1] in {"rm", "remove"}:
        forced = any(
            arg in {"-f", "--force"} or (arg.startswith("-") and not arg.startswith("--") and "f" in arg[1:])
            for arg in tokens[2:]
        )
        if forced:
            return (
                "Blocked forced `ws rm --force`. "
                "Run `ws rm <name>` without `-f` so dirty or unmerged worktrees are protected, or ask the user first."
            )
    return None


def main() -> int:
    command = sys.stdin.read()
    if not command.strip():
        return 0

    for segment in split_segments(command):
        cleaned = strip_prefixes(segment)
        if not cleaned:
            continue
        cmd = Path(cleaned[0]).name
        reason: str | None = None
        if cmd == "rm":
            reason = check_rm(cleaned)
        elif cmd == "git":
            reason = check_git(cleaned)
        elif cmd == "ws":
            reason = check_ws(cleaned)
        if reason:
            sys.stderr.write(f"{reason}\n")
            return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
