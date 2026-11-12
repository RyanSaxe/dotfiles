"""Behavioral tests for config/zsh/prompt-segments.sh, run against throwaway repos.

Each run gets a scratch HOME and cache and an environment built from
nothing, so no GIT_* variable from a calling hook can point git at another
repository. Stdlib-only imports: the type checker's
environment has no pytest; the built-in tmp_path fixture arrives by
argument name.
"""

from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path

REPO = Path(__file__).parent.parent.parent
SCRIPT = REPO / "config/zsh/prompt-segments.sh"
DASH = shutil.which("dash") or "/bin/dash"


def scratch_env(home: Path) -> dict[str, str]:
    return {
        "PATH": os.environ["PATH"],
        "HOME": str(home),
        "XDG_CACHE_HOME": str(home / ".cache"),
        "GIT_CONFIG_GLOBAL": "/dev/null",
        "GIT_CONFIG_NOSYSTEM": "1",
    }


def make_home(tmp_path: Path) -> Path:
    # git reports canonical paths, so HOME must be canonical for the prompt
    # to abbreviate it as ~.
    home = tmp_path.resolve() / "home"
    home.mkdir()
    return home


def make_repo(home: Path, path: Path) -> Path:
    path.mkdir(parents=True)

    def git(*args: str) -> str:
        return subprocess.run(
            ["git", *args],
            cwd=path,
            env=scratch_env(home),
            capture_output=True,
            text=True,
            check=True,
        ).stdout.strip()

    git("init", "-q", "-b", "main")
    assert git("rev-parse", "--show-toplevel") == str(path)
    git(
        "-c",
        "user.name=t",
        "-c",
        "user.email=t@t",
        "commit",
        "-q",
        "--allow-empty",
        "-m",
        "one",
    )
    return path


def segments(
    home: Path, cwd: Path, extra: dict[str, str] | None = None
) -> dict[str, str]:
    result = subprocess.run(
        [DASH, str(SCRIPT)],
        cwd=cwd,
        env={**scratch_env(home), **(extra or {})},
        capture_output=True,
        text=True,
        check=True,
    )
    assert result.stderr == ""
    return dict(line.split("\x1f", 1) for line in result.stdout.splitlines())


def test_deep_repo_parent_collapses(tmp_path: Path) -> None:
    home = make_home(tmp_path)
    repo = make_repo(home, home / "a/b/c/d/deep")
    assert segments(home, repo)["REPO_PARENT"] == "~/…/c/d"


def test_shallow_repo_parent_stays_whole(tmp_path: Path) -> None:
    home = make_home(tmp_path)
    repo = make_repo(home, home / "a/shallow")
    assert segments(home, repo)["REPO_PARENT"] == "~/a"


def test_deleted_directory_shows_only_where_it_was(tmp_path: Path) -> None:
    home = make_home(tmp_path)
    gone = home / "a/b/c/d/gone"
    assert segments(home, Path("/"), {"_PROMPT_GONE": str(gone)}) == {
        "DIR_PLAIN": "~/…/c/d",
        "GONE": "gone",
    }
