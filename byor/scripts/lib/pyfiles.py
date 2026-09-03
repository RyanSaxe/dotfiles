#!/usr/bin/env python3
# /// script
# requires-python = ">=3.12"
# dependencies = []
# ///
"""List the Python files a sibling check script should scan.

Given trailing path arguments, it echoes back the ones that are existing
Python files; given none, it discovers the repository's Python files with
`git ls-files -coz --exclude-standard`, falling back to a filtered directory
walk when git is unavailable. Paths are written to stdout NUL-delimited so
any filename, including one with spaces or newlines, round-trips
unambiguously. A nonzero exit means the listing itself failed, never "no
files found".

This file is also a teaching example: byor check scripts share code as
path-referenced subprocesses, never as Python imports, because `byor gate`
vendors `~/.config/byor/scripts/` files into repos by scanning script text
for literal `~/.config/byor/scripts/<subpath>` references and rewriting them
to `.byor/scripts/<subpath>`. The sibling checks here already live in the
repo, so they resolve this file relative to their own location
(`Path(__file__).parent / "lib" / "pyfiles.py"`); a home-directory script
must instead embed the literal `~/.config/byor/scripts/lib/pyfiles.py`
string, because the `__file__`-relative form is invisible to the vendoring
scanner.
"""

from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path

PYTHON_SUFFIXES = frozenset({".py", ".pyi"})
EXCLUDED_WALK_DIRS = frozenset({".git", ".venv", "venv", "node_modules", "__pycache__", ".tox", "dist", "build"})


def main(argv: list[str]) -> int:
    candidates = [Path(raw) for raw in argv] if argv else _repo_python_files()
    for path in candidates:
        if path.suffix in PYTHON_SUFFIXES and path.is_file():
            sys.stdout.write(f"{path}\0")
    return 0


def _repo_python_files() -> list[Path]:
    git = shutil.which("git")
    if git is None:
        return _walk_python_files(Path.cwd())
    root = _git_root(Path.cwd(), git=git)
    if root is None:
        return _walk_python_files(Path.cwd())
    try:
        completed = subprocess.run(
            (
                git,
                "-C",
                str(root),
                "ls-files",
                "-coz",
                "--exclude-standard",
                "--",
                "*.py",
                "*.pyi",
            ),
            check=False,
            capture_output=True,
            text=True,
        )
    except FileNotFoundError:
        return _walk_python_files(root)
    if completed.returncode != 0:
        return _walk_python_files(root)
    # -z NUL-delimits entries and disables core.quotePath mangling, so
    # filenames with newlines or non-ASCII characters round-trip intact.
    return [root / entry for entry in completed.stdout.split("\0") if entry]


def _git_root(start: Path, *, git: str) -> Path | None:
    anchor = start if start.is_dir() else start.parent
    try:
        completed = subprocess.run(
            (git, "-C", str(anchor), "rev-parse", "--show-toplevel"),
            check=False,
            capture_output=True,
            text=True,
        )
    except FileNotFoundError:
        return None
    if completed.returncode != 0:
        return None
    root = completed.stdout.strip()
    return Path(root) if root else None


def _walk_python_files(root: Path) -> list[Path]:
    return [
        path
        for path in root.rglob("*")
        if path.suffix in PYTHON_SUFFIXES
        and path.is_file()
        and not EXCLUDED_WALK_DIRS.intersection(path.relative_to(root).parts)
    ]


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
