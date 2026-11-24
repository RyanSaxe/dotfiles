#!/usr/bin/env python3
"""Warn when a source file grows past 600 lines.

Just-in-time steering check for the BYOR `craft` package (`gate: false`).
Prompts the agent to consider splitting along a natural domain boundary well
before hitting the 1,000-line hard cap enforced in prek and CI.
"""

from __future__ import annotations

import sys
from pathlib import Path

WARN_LINES = 600
HARD_CAP_LINES = 1000
GENERATED_PARTS = {"node_modules", ".venv", "dist", "build", "target", "__pycache__"}


def is_generated_or_minified(path: Path) -> bool:
    if any(part in GENERATED_PARTS for part in path.parts):
        return True
    name = path.name
    return name.endswith((".min.js", ".min.css", ".d.ts", ".generated.ts", ".generated.py"))


def main(argv: list[str]) -> int:
    findings: list[str] = []
    for raw in argv:
        path = Path(raw)
        if not path.is_file() or is_generated_or_minified(path):
            continue
        try:
            line_count = len(path.read_text(encoding="utf-8", errors="replace").splitlines())
        except OSError:
            continue
        if line_count > WARN_LINES:
            findings.append(
                f"{raw}: {line_count} lines (soft threshold {WARN_LINES}, hard prek cap {HARD_CAP_LINES}). "
                "Consider splitting cohesive responsibilities along a domain boundary instead of growing this file."
            )
    if findings:
        sys.stdout.write("\n".join(findings) + "\n")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
