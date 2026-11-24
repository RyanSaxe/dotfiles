#!/usr/bin/env python3
"""Flag 1-2 line function, method, and class docstrings across languages.

Just-in-time steering check (`gate: false`) for the BYOR `craft` package.
Skips module headers and Lua EmmyLua `@type`/`@param`/`@return` annotation
blocks. Encourages deleting docstrings that merely restate names and types, or
expanding them only when they explain non-obvious invariants or constraints.
"""

from __future__ import annotations

import ast
import re
import sys
from pathlib import Path

PY_EXTS = {".py", ".pyi"}
JS_EXTS = {".ts", ".tsx", ".js", ".jsx"}
RUST_EXTS = {".rs"}
LUA_EXTS = {".lua"}

JS_DECL_RE = re.compile(
    r"^\s*(?:export\s+(?:default\s+)?)?(?:async\s+)?(?:function\s+([A-Za-z_$]\w*)|class\s+([A-Za-z_$]\w*)|(?:const|let)\s+([A-Za-z_$]\w*)\s*=|([A-Za-z_$]\w*)\s*\()"
)
RUST_DECL_RE = re.compile(
    r"^\s*(?:pub(?:\([^)]*\))?\s+)?(?:async\s+)?(?:unsafe\s+)?(?:fn|struct|enum|trait)\s+([A-Za-z_]\w*)"
)
LUA_DECL_RE = re.compile(r"^\s*(?:local\s+)?function\s+([A-Za-z_][\w.:]*)")
DELETE_PROMPT = (
    "Delete it completely (do not replace it with a `#` or `//` comment that restates the signature); "
    "expand only to document non-obvious invariants or constraints."
)
LUA_DELETE_PROMPT = (
    "Delete prose that restates the name (keep `@param`/`@return` type annotations, and do not replace it with a "
    "`--` comment that restates the signature); expand only to document a non-obvious invariant."
)


def check_python(raw: str, text: str) -> list[str]:
    try:
        tree = ast.parse(text)
    except SyntaxError:
        return []
    findings: list[str] = []
    for node in ast.walk(tree):
        if not isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
            continue
        doc = ast.get_docstring(node, clean=True)
        if not doc:
            continue
        non_empty = [line for line in doc.splitlines() if line.strip()]
        if 1 <= len(non_empty) <= 2:
            findings.append(
                f"{raw}:{node.lineno}: thin {len(non_empty)}-line docstring on `{node.name}`. {DELETE_PROMPT}"
            )
    return findings


def check_js(raw: str, text: str) -> list[str]:
    lines = text.splitlines()
    findings: list[str] = []
    idx = 0
    # Skip leading module header comment block if present at top of file.
    while idx < len(lines) and (not lines[idx].strip() or lines[idx].startswith("#!")):
        idx += 1
    if idx < len(lines) and lines[idx].strip().startswith("/*"):
        while idx < len(lines) and "*/" not in lines[idx]:
            idx += 1
        idx += 1

    while idx < len(lines):
        line = lines[idx].strip()
        if line.startswith("/**"):
            start = idx
            block: list[str] = []
            while idx < len(lines):
                block.append(lines[idx])
                if "*/" in lines[idx]:
                    break
                idx += 1
            next_idx = idx + 1
            while next_idx < len(lines) and not lines[next_idx].strip():
                next_idx += 1
            if next_idx < len(lines):
                match = JS_DECL_RE.match(lines[next_idx])
                if match:
                    cleaned_lines: list[str] = []
                    for raw_line in block:
                        s = raw_line.strip()
                        s = re.sub(r"^/\*\*+", "", s)
                        s = re.sub(r"\*/$", "", s)
                        s = re.sub(r"^\*\s?", "", s).strip()
                        if s:
                            cleaned_lines.append(s)
                    if 1 <= len(cleaned_lines) <= 2:
                        name = next((g for g in match.groups() if g), "declaration")
                        findings.append(
                            f"{raw}:{start + 1}: thin {len(cleaned_lines)}-line JSDoc on `{name}`. {DELETE_PROMPT}"
                        )
        idx += 1
    return findings


def check_rust(raw: str, text: str) -> list[str]:
    lines = text.splitlines()
    findings: list[str] = []
    idx = 0
    while idx < len(lines):
        if lines[idx].strip().startswith("///"):
            start = idx
            doc_lines: list[str] = []
            while idx < len(lines) and lines[idx].strip().startswith("///"):
                content = lines[idx].strip()[3:].strip()
                if content:
                    doc_lines.append(content)
                idx += 1
            # Skip attribute lines like #[inline] between doc comment and item.
            decl_idx = idx
            while decl_idx < len(lines) and lines[decl_idx].strip().startswith("#["):
                decl_idx += 1
            if decl_idx < len(lines) and 1 <= len(doc_lines) <= 2:
                match = RUST_DECL_RE.match(lines[decl_idx])
                if match:
                    findings.append(
                        f"{raw}:{start + 1}: thin {len(doc_lines)}-line doc comment on `{match.group(1)}`. {DELETE_PROMPT}"
                    )
            continue
        idx += 1
    return findings


def check_lua(raw: str, text: str) -> list[str]:
    lines = text.splitlines()
    findings: list[str] = []
    idx = 0
    while idx < len(lines):
        if lines[idx].strip().startswith("---"):
            start = idx
            prose_lines: list[str] = []
            while idx < len(lines) and lines[idx].strip().startswith("---"):
                content = lines[idx].strip()[3:].strip()
                # Ignore EmmyLua type annotations (@param, @return, @type, @class, @field, etc.).
                if content and not content.startswith("@"):
                    prose_lines.append(content)
                idx += 1
            if idx < len(lines) and 1 <= len(prose_lines) <= 2:
                match = LUA_DECL_RE.match(lines[idx])
                if match:
                    findings.append(
                        f"{raw}:{start + 1}: thin {len(prose_lines)}-line Lua doc comment on `{match.group(1)}`. "
                        f"{LUA_DELETE_PROMPT}"
                    )
            continue
        idx += 1
    return findings


def main(argv: list[str]) -> int:
    findings: list[str] = []
    for raw in argv:
        path = Path(raw)
        if not path.is_file():
            continue
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        ext = path.suffix
        if ext in PY_EXTS:
            findings.extend(check_python(raw, text))
        elif ext in JS_EXTS:
            findings.extend(check_js(raw, text))
        elif ext in RUST_EXTS:
            findings.extend(check_rust(raw, text))
        elif ext in LUA_EXTS:
            findings.extend(check_lua(raw, text))

    if findings:
        sys.stdout.write("\n".join(findings) + "\n")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
