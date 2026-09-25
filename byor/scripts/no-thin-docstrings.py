#!/usr/bin/env python3
# /// script
# requires-python = ">=3.12"
# dependencies = []
# ///
"""Reject thin docstrings on classes, methods, and functions.

Function-level docstrings should be rare in greenfield code because strong
names, precise type signatures, and straightforward bodies usually explain the
contract better than a redundant sentence. Keep one only for public APIs that
need real argument and behavior documentation, or for complex signatures whose
meaning requires one or more explanatory paragraphs. File discovery is shared
with the sibling checks via the `lib/pyfiles.py` subprocess (see its
docstring).
"""

from __future__ import annotations

import ast
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

PYFILES_LIB = Path("~/.config/byor/scripts/lib/pyfiles.py").expanduser()
MAX_THIN_LINES = 3
THIN_DOCSTRING_ADVICE = (
    "delete it if the signature and body are enough, or expand it into "
    "full public/complexity docs with arguments, behavior, edge cases, "
    "and examples where useful; when expanding, build on what it already "
    "says — never swap real information for generic filler"
)

DOC_NODES = (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)


@dataclass(frozen=True)
class _Finding:
    path: Path
    line: int
    message: str


def main(argv: list[str]) -> int:
    findings = [finding for path in _python_files(argv) for finding in _check(path)]
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


def _check(path: Path) -> list[_Finding]:
    try:
        source = path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        return [_Finding(path, 1, "file is not valid UTF-8; fix the encoding")]
    try:
        module = ast.parse(source, filename=str(path))
    except SyntaxError as error:
        return [_Finding(path, error.lineno or 1, _parse_failure_message(error))]
    findings: list[_Finding] = []
    for node in ast.walk(module):
        if not isinstance(node, DOC_NODES):
            continue
        docstring = ast.get_docstring(node)
        if docstring is None:
            continue
        if len(_meaningful_lines(docstring)) <= MAX_THIN_LINES:
            message = f"thin docstring on {_label(node)}; {THIN_DOCSTRING_ADVICE}"
            findings.append(_Finding(path, _docstring_line(node), message))
    return findings


def _parse_failure_message(error: SyntaxError) -> str:
    runtime = ".".join(str(part) for part in sys.version_info[:2])
    return f"cannot be parsed by Python {runtime} ({error.msg}); fix the syntax or run this check on a newer Python"


def _meaningful_lines(docstring: str) -> list[str]:
    return [line.strip() for line in docstring.strip("\n").splitlines() if line.strip()]


def _docstring_line(node: ast.FunctionDef | ast.AsyncFunctionDef | ast.ClassDef) -> int:
    if not node.body:
        return getattr(node, "lineno", 1)
    return getattr(node.body[0], "lineno", getattr(node, "lineno", 1))


def _label(node: ast.FunctionDef | ast.AsyncFunctionDef | ast.ClassDef) -> str:
    kind = "class" if isinstance(node, ast.ClassDef) else "function/method"
    return f"{kind} `{node.name}`"


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
