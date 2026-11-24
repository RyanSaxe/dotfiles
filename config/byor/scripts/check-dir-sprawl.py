#!/usr/bin/env python3
"""Nudge when adding a new source file pushes a directory to 10+ siblings.

Just-in-time steering check (`gate: false`) for the BYOR `craft` package.
Fires only for newly created non-test source files (not yet in `HEAD`) so
editing existing files never produces noise, preventing flat dumping-ground
directories caused by mechanical file-size splits.
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

SPRAWL_THRESHOLD = 10
SOURCE_EXTS = {".py", ".pyi", ".ts", ".tsx", ".mts", ".cts", ".js", ".jsx", ".mjs", ".cjs", ".rs", ".go", ".lua"}
TEST_DIRS = {"tests", "test", "__tests__", "spec", "specs"}
INDEX_MARKERS = {"__init__.py", "index.ts", "index.tsx", "index.js", "index.jsx", "mod.rs"}


def is_test_path(path: Path) -> bool:
    if {part.lower() for part in path.parts[:-1]} & TEST_DIRS:
        return True
    name = path.name.lower()
    if name in {"conftest.py"} or name.startswith("test_") or name.endswith(("_test.py", "_test.go", "_spec.lua")):
        return True
    return any(marker in name for marker in (".test.", ".spec."))


def is_new_vs_head(path: Path) -> bool:
    try:
        rel = path.resolve().relative_to(Path.cwd().resolve()).as_posix()
    except ValueError:
        return False
    in_git = subprocess.run(["git", "rev-parse", "--is-inside-work-tree"], capture_output=True, check=False)
    if in_git.returncode != 0:
        return True
    exists = subprocess.run(["git", "cat-file", "-e", f"HEAD:{rel}"], capture_output=True, check=False)
    return exists.returncode != 0


def count_sibling_sources(directory: Path) -> int:
    count = 0
    for child in directory.iterdir():
        if not child.is_file():
            continue
        if child.suffix not in SOURCE_EXTS or child.name in INDEX_MARKERS:
            continue
        if is_test_path(child):
            continue
        count += 1
    return count


def main(argv: list[str]) -> int:
    findings: list[str] = []
    warned_dirs: set[Path] = set()
    for raw in argv:
        path = Path(raw)
        if not path.is_file() or path.suffix not in SOURCE_EXTS or path.name in INDEX_MARKERS:
            continue
        if is_test_path(path):
            continue
        if not is_new_vs_head(path):
            continue
        parent = path.parent.resolve()
        if parent in warned_dirs:
            continue
        sibling_count = count_sibling_sources(parent)
        if sibling_count >= SPRAWL_THRESHOLD:
            warned_dirs.add(parent)
            try:
                rel_dir = parent.relative_to(Path.cwd().resolve()).as_posix()
            except ValueError:
                rel_dir = str(parent)
            findings.append(
                f"{raw}: `{rel_dir}/` now contains {sibling_count} sibling source files (threshold {SPRAWL_THRESHOLD}). "
                "Check whether this directory is becoming a flat dumping ground and should be grouped into cohesive domain subdirectories."
            )

    if findings:
        sys.stdout.write("\n".join(findings) + "\n")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
