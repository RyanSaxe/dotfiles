#!/usr/bin/env python3
# /// script
# requires-python = ">=3.12"
# dependencies = []
# ///
"""Reject thin docstrings, and comments standing in for them, on classes,
methods, and functions.

Function-level docstrings should be rare in greenfield code because strong
names, precise type signatures, and straightforward bodies usually explain the
contract better than a redundant sentence. Keep one only for public APIs that
need real argument and behavior documentation, or for complex signatures whose
meaning requires one or more explanatory paragraphs. File discovery is shared
with the sibling checks via the `lib/pyfiles.py` subprocess (see its
docstring).

A definition must also never open with a `#` comment as its first body line:
that is a docstring wearing the wrong syntax. It should be a real docstring if
it carries a contract worth keeping, or nothing at all. Comments are absent
from the `ast`, so a `tokenize` pass finds these.
"""

from __future__ import annotations

import ast
import io
import subprocess
import sys
import tokenize
from dataclasses import dataclass
from pathlib import Path

PYFILES_LIB = Path(__file__).resolve().parent / "lib" / "pyfiles.py"
MAX_THIN_LINES = 3
THIN_DOCSTRING_ADVICE = (
    "delete it if the signature and body are enough, or expand it into "
    "full public/complexity docs with arguments, behavior, edge cases, "
    "and examples where useful; when expanding, build on what it already "
    "says — never swap real information for generic filler"
)
LEADING_COMMENT_ADVICE = (
    "a definition must not open with a comment as its first body line; "
    "make it a real docstring if it states a contract worth keeping, or "
    "delete it"
)

DOC_NODES = (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)
DEFINITION_KEYWORDS = frozenset({"def", "class"})


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
    findings.extend(_leading_comment_findings(source, path))
    return findings


def _leading_comment_findings(source: str, path: Path) -> list[_Finding]:
    try:
        tokens = list(tokenize.generate_tokens(io.StringIO(source).readline))
    except (tokenize.TokenError, IndentationError, SyntaxError):
        return []  # ast.parse already reported anything unparseable
    findings: list[_Finding] = []
    for index, token in enumerate(tokens):
        if token.type != tokenize.NAME or token.string not in DEFINITION_KEYWORDS:
            continue
        first = _first_body_token(tokens, index)
        if first is not None and first.type == tokenize.COMMENT:
            label = f"{token.string} `{_definition_name(tokens, index)}`"
            findings.append(
                _Finding(
                    path,
                    first.start[0],
                    f"leading comment on {label}; {LEADING_COMMENT_ADVICE}",
                )
            )
    return findings


def _definition_name(tokens: list[tokenize.TokenInfo], keyword_index: int) -> str:
    following = tokens[keyword_index + 1] if keyword_index + 1 < len(tokens) else None
    return (
        following.string
        if following and following.type == tokenize.NAME
        else "<anonymous>"
    )


def _first_body_token(tokens: list[tokenize.TokenInfo], keyword_index: int):
    depth = 0
    cursor = keyword_index + 1
    while cursor < len(tokens):
        token = tokens[cursor]
        if token.type == tokenize.OP and token.string in "([{":
            depth += 1
        elif token.type == tokenize.OP and token.string in ")]}":
            depth -= 1
        elif token.type == tokenize.OP and token.string == ":" and depth == 0:
            break
        cursor += 1
    else:
        return None
    cursor += 1
    while cursor < len(tokens):  # walk the signature line to its NEWLINE
        token = tokens[cursor]
        if token.type == tokenize.NEWLINE:
            break
        if token.type != tokenize.COMMENT:
            return token  # a one-line body: no leading-comment position exists
        cursor += 1
    else:
        return None
    cursor += 1
    while cursor < len(tokens) and tokens[cursor].type in (
        tokenize.INDENT,
        tokenize.NL,
        tokenize.NEWLINE,
    ):
        cursor += 1
    return tokens[cursor] if cursor < len(tokens) else None


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
