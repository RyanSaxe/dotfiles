#!/usr/bin/env python3
"""Require a reason comment on newly added lint or type-check suppressions.

Just-in-time steering check (`gate: false`) for the BYOR `craft` package.
Inspects only newly added lines (diff against `HEAD`, or all lines for an
untracked file) so existing suppressions are untouched.
"""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

SUPPRESSION_RE = re.compile(
    r"(?P<marker>"
    r"#\s*noqa(?::\s*[\w]+(?:\s*,\s*[\w]+)*)?|"
    r"#\s*ty:\s*ignore(?:\[[^\]]+\])?|"
    r"#\s*type:\s*ignore(?:\[[^\]]+\])?|"
    r"oxlint-disable(?:-next-line|-line)?(?:\s+[\w/@]+(?:-[\w/@]+)*(?:\s*,\s*[\w/@]+(?:-[\w/@]+)*)*)?|"
    r"@ts-(?:expect-error|ignore|nocheck)|"
    r"ast-grep-ignore(?::\s*[\w./]+(?:-[\w./]+)*(?:\s*,\s*[\w./]+(?:-[\w./]+)*)*)?|"
    r"#\[allow\([^)]+\)\]|"
    r"//\s*nolint(?::[\w]+(?:-[\w]+)*(?:,[\w]+(?:-[\w]+)*)*)?"
    r")",
    re.IGNORECASE,
)
COMMENT_PREFIX_RE = re.compile(r"^\s*(?:#|//|/\*|\*|--)\s*(.+)$")
MIN_REASON_WORDS = 2
MAX_LOOKBACK_LINES = 2
HUNK_RE = re.compile(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@")


def _parse_diff_added_lines(diff_text: str) -> list[tuple[int, str]]:
    added: list[tuple[int, str]] = []
    current_line = 0
    for line in diff_text.splitlines():
        hunk = HUNK_RE.match(line)
        if hunk:
            current_line = int(hunk.group(1))
            continue
        if line.startswith(("+++", "---")):
            continue
        if line.startswith("+"):
            added.append((current_line, line[1:]))
            current_line += 1
        elif not line.startswith("-"):
            current_line += 1
    return added


def added_lines_for(path: Path) -> list[tuple[int, str]]:
    """Return (1-based line_no, text) for newly added lines vs HEAD (or all lines if untracked)."""
    try:
        rel = path.resolve().relative_to(Path.cwd().resolve()).as_posix()
    except ValueError:
        rel = str(path)

    tracked = subprocess.run(["git", "cat-file", "-e", f"HEAD:{rel}"], capture_output=True, check=False)
    if tracked.returncode != 0:
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
        return [(idx + 1, line) for idx, line in enumerate(lines)]

    diff = subprocess.run(
        ["git", "diff", "HEAD", "-U0", "--", rel],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
    )
    if diff.returncode != 0:
        return []
    return _parse_diff_added_lines(diff.stdout)


def has_inline_reason(line: str, match_end: int) -> bool:
    tail = line[match_end:].strip()
    # Strip leading separators like `--`, `#`, `//`, `:`, `-`, `*/`.
    tail = re.sub(r"^(?:--|//|#|:|-|\s)+", "", tail)
    tail = re.sub(r"\*/\s*$", "", tail).strip()
    words = re.findall(r"[A-Za-z]{2,}", tail)
    return len(words) >= MIN_REASON_WORDS


def has_preceding_reason(all_lines: list[str], line_no: int) -> bool:
    idx = line_no - 2  # 0-based line immediately above
    checked = 0
    while idx >= 0 and checked < MAX_LOOKBACK_LINES:
        prev = all_lines[idx]
        if not prev.strip():
            break
        if SUPPRESSION_RE.search(prev):
            idx -= 1
            continue
        comment = COMMENT_PREFIX_RE.match(prev)
        if comment:
            words = re.findall(r"[A-Za-z]{2,}", comment.group(1))
            if len(words) >= MIN_REASON_WORDS:
                return True
        break
    return False


def check_file(raw: str) -> list[str]:
    path = Path(raw)
    if not path.is_file():
        return []
    try:
        all_lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError:
        return []

    findings: list[str] = []
    for line_no, line in added_lines_for(path):
        match = SUPPRESSION_RE.search(line)
        if not match:
            continue
        if has_inline_reason(line, match.end()) or has_preceding_reason(all_lines, line_no):
            continue
        marker = match.group("marker").strip()
        findings.append(
            f"{raw}:{line_no}: newly added suppression `{marker}` has no explanation. "
            "Fix the underlying issue if possible; if the suppression is justified, add a short reason inline "
            "(`-- reason` / `// reason`) or on the comment line directly above."
        )
    return findings


def main(argv: list[str]) -> int:
    findings: list[str] = []
    for raw in argv:
        findings.extend(check_file(raw))
    if findings:
        sys.stdout.write("\n".join(findings) + "\n")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
