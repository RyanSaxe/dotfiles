#!/usr/bin/env python3
# /// script
# requires-python = ">=3.12"
# dependencies = []
# ///
"""Reject Python comments that suppress diagnostics.

The check scans Python comments for suppression directives such as noqa,
type-ignore, tool-specific ignore comments, and coverage pragmas. Comments are
located with the tokenize module, so markers inside string literals do not
count; syntactically broken files fall back to a plain line scan. Greenfield
code should fix the underlying problem instead of hiding it from agents,
reviewers, linters, or type checkers. File discovery is shared with the
sibling checks via the `lib/pyfiles.py` subprocess (see its docstring).
"""

from __future__ import annotations

import io
import re
import subprocess
import sys
import tokenize
from dataclasses import dataclass
from pathlib import Path

PYFILES_LIB = Path("~/.config/byor/scripts/lib/pyfiles.py").expanduser()


@dataclass(frozen=True)
class _SuppressionPattern:
    name: str
    regex: re.Pattern[str]


@dataclass(frozen=True)
class _Finding:
    path: Path
    line: int
    message: str


PATTERNS = [
    _SuppressionPattern(
        "noqa", re.compile(r"#\s*(?:noqa|ruff:\s*noqa|flake8:\s*noqa)\b")
    ),
    _SuppressionPattern("type ignore", re.compile(r"#\s*type:\s*ignore\b")),
    _SuppressionPattern("ty ignore", re.compile(r"#\s*ty:\s*ignore\b")),
    _SuppressionPattern(
        "pyright suppression",
        re.compile(r"#\s*pyright:\s*(?:ignore|report[A-Za-z0-9_]+\s*=)\b"),
    ),
    _SuppressionPattern(
        "mypy suppression",
        re.compile(
            r"#\s*mypy:\s*(?:ignore-errors|disable-error-code|allow-|disable-)\b"
        ),
    ),
    _SuppressionPattern("pylint disable", re.compile(r"#\s*pylint:\s*disable\b")),
    _SuppressionPattern("pyre ignore", re.compile(r"#\s*pyre-(?:ignore|fixme)\b")),
    _SuppressionPattern("pytype disable", re.compile(r"#\s*pytype:\s*disable\b")),
    _SuppressionPattern("coverage pragma", re.compile(r"#\s*pragma:\s*no cover\b")),
]


def main(argv: list[str]) -> int:
    findings = [finding for path in _python_files(argv) for finding in _scan(path)]
    for finding in findings:
        sys.stdout.write(f"{finding.path}:{finding.line}: {finding.message}\n")
    return 1 if findings else 0


def _python_files(argv: list[str]) -> list[Path]:
    completed = subprocess.run(
        (sys.executable, str(PYFILES_LIB), *argv),
        check=True,
        stdout=subprocess.PIPE,
        text=True,
    )
    return [Path(raw) for raw in completed.stdout.split("\0") if raw]


def _scan(path: Path) -> list[_Finding]:
    try:
        source = path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        return [_Finding(path, 1, "file is not valid UTF-8; fix the encoding")]
    findings: list[_Finding] = []
    for line_number, comment in _comments(source):
        for pattern in PATTERNS:
            if pattern.regex.search(comment):
                findings.append(
                    _Finding(
                        path,
                        line_number,
                        f"{pattern.name} suppression comment is not allowed",
                    )
                )
                break
    return findings


def _comments(source: str) -> list[tuple[int, str]]:
    try:
        tokens = list(tokenize.generate_tokens(io.StringIO(source).readline))
    except (tokenize.TokenError, SyntaxError):
        return _comment_like_line_tails(source)
    return [
        (token.start[0], token.string)
        for token in tokens
        if token.type == tokenize.COMMENT
    ]


def _comment_like_line_tails(source: str) -> list[tuple[int, str]]:
    tails: list[tuple[int, str]] = []
    for line_number, line in enumerate(source.splitlines(), 1):
        comment_index = line.find("#")
        if comment_index != -1:
            tails.append((line_number, line[comment_index:]))
    return tails


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
