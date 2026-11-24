#!/usr/bin/env python3
"""Check source-file module header presence and export-drift freshness.

Cross-language steering check (`gate: false`) for the BYOR `craft` package.
Checks Python, TypeScript/JavaScript, Rust, Go, and Lua source files (skipping
tests and empty marker `__init__.py`). Reports:
1. Missing top-of-file module header comment/docstring.
2. Public export additions or removals compared to `HEAD` when the module
   header text stayed unchanged.
"""

from __future__ import annotations

import ast
import re
import subprocess
import sys
from pathlib import Path

TEST_DIRS = {"tests", "test", "__tests__", "spec", "specs"}
PY_EXTS = {".py", ".pyi"}
JS_EXTS = {".ts", ".tsx", ".mts", ".cts", ".js", ".jsx", ".mjs", ".cjs"}
RUST_EXTS = {".rs"}
GO_EXTS = {".go"}
LUA_EXTS = {".lua"}

JS_EXPORT_RE = re.compile(
    r"^\s*export\s+(?:default\s+)?(?:async\s+)?(?:function|class|const|let|var|type|interface|enum)\s+([A-Za-z_$][\w$]*)",
    re.MULTILINE,
)
RUST_PUB_RE = re.compile(
    r"^\s*pub(?:\([^)]*\))?\s+(?:async\s+)?(?:unsafe\s+)?(?:const\s+)?(?:fn|struct|enum|trait|type|const|static|mod)\s+([A-Za-z_]\w*)",
    re.MULTILINE,
)
GO_EXPORT_RE = re.compile(
    r"^(?:func\s+(?:\([^)]*\)\s*)?|type\s+|var\s+|const\s+)([A-Z]\w*)",
    re.MULTILINE,
)
LUA_EXPORT_RE = re.compile(
    r"^(?:function\s+[A-Za-z_]\w*\.([A-Za-z_]\w*)|M\.([A-Za-z_]\w*)\s*=)",
    re.MULTILINE,
)


def is_test_file(path: Path) -> bool:
    parts = {part.lower() for part in path.parts[:-1]}
    if parts & TEST_DIRS:
        return True
    name = path.name.lower()
    if name == "conftest.py":
        return True
    if name.startswith("test_") or name.endswith(("_test.py", "_test.go", "_spec.lua")):
        return True
    return any(marker in name for marker in (".test.", ".spec."))


def is_empty_init_py(path: Path, text: str) -> bool:
    if path.name != "__init__.py":
        return False
    stripped = [line.strip() for line in text.splitlines() if line.strip() and not line.strip().startswith("#")]
    return len(stripped) == 0


def extract_python_header_and_exports(text: str) -> tuple[str | None, set[str]]:
    try:
        tree = ast.parse(text)
    except SyntaxError:
        return "syntax-error", set()
    header = ast.get_docstring(tree)
    exports: set[str] = set()
    for node in tree.body:
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)) and not node.name.startswith("_"):
            exports.add(node.name)
    return header, exports


def extract_js_header_and_exports(text: str) -> tuple[str | None, set[str]]:
    lines = text.splitlines()
    idx = 0
    if idx < len(lines) and lines[idx].startswith("#!"):
        idx += 1
    while idx < len(lines):
        s = lines[idx].strip()
        if not s or s in {
            '"use strict";',
            "'use strict';",
            '"use client";',
            "'use client';",
            '"use server";',
            "'use server';",
            '"use strict"',
            "'use strict'",
            '"use client"',
            "'use client'",
        }:
            idx += 1
            continue
        break

    header_lines: list[str] = []
    if idx < len(lines):
        s = lines[idx].strip()
        if s.startswith("/*"):
            while idx < len(lines):
                header_lines.append(lines[idx])
                if "*/" in lines[idx]:
                    break
                idx += 1
        elif s.startswith("//"):
            while idx < len(lines) and lines[idx].strip().startswith("//"):
                header_lines.append(lines[idx])
                idx += 1

    header = "\n".join(header_lines).strip() or None
    exports = set(JS_EXPORT_RE.findall(text))
    return header, exports


def extract_rust_header_and_exports(text: str) -> tuple[str | None, set[str]]:
    header_lines: list[str] = []
    for line in text.splitlines():
        s = line.strip()
        if not s:
            continue
        if s.startswith("//!"):
            header_lines.append(s)
            continue
        if s.startswith("#!["):
            continue
        break
    header = "\n".join(header_lines).strip() or None
    exports = set(RUST_PUB_RE.findall(text))
    return header, exports


def extract_go_header_and_exports(text: str) -> tuple[str | None, set[str]]:
    lines = text.splitlines()
    pkg_idx = next((i for i, line in enumerate(lines) if re.match(r"^\s*package\s+\w+", line)), None)
    if pkg_idx is None:
        return None, set()
    comment_lines: list[str] = []
    idx = pkg_idx - 1
    while idx >= 0:
        s = lines[idx].strip()
        if not s:
            if comment_lines:
                break
            idx -= 1
            continue
        if s.startswith(("//", "/*", "*")) or s.endswith("*/"):
            comment_lines.append(s)
            idx -= 1
            continue
        break
    header = "\n".join(reversed(comment_lines)).strip() or None
    exports = set(GO_EXPORT_RE.findall(text))
    return header, exports


def extract_lua_header_and_exports(text: str) -> tuple[str | None, set[str]]:
    lines = text.splitlines()
    idx = 0
    if idx < len(lines) and lines[idx].startswith("#!"):
        idx += 1
    while idx < len(lines) and not lines[idx].strip():
        idx += 1
    header_lines: list[str] = []
    while idx < len(lines) and lines[idx].strip().startswith("--"):
        header_lines.append(lines[idx])
        idx += 1
    header = "\n".join(header_lines).strip() or None
    exports = {m[0] or m[1] for m in LUA_EXPORT_RE.findall(text) if m[0] or m[1]}
    return header, exports


def extract(path: Path, text: str) -> tuple[str | None, set[str]] | None:
    ext = path.suffix
    if ext in PY_EXTS:
        return extract_python_header_and_exports(text)
    if ext in JS_EXTS:
        return extract_js_header_and_exports(text)
    if ext in RUST_EXTS:
        return extract_rust_header_and_exports(text)
    if ext in GO_EXTS:
        return extract_go_header_and_exports(text)
    if ext in LUA_EXTS:
        return extract_lua_header_and_exports(text)
    return None


def read_head_version(path: Path) -> str | None:
    try:
        rel = path.resolve().relative_to(Path.cwd().resolve()).as_posix()
    except ValueError:
        return None
    result = subprocess.run(
        ["git", "show", f"HEAD:{rel}"],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
    )
    return result.stdout if result.returncode == 0 else None


def _check_export_drift(raw: str, path: Path, *, header: str, exports: set[str]) -> str | None:
    head_text = read_head_version(path)
    head_extracted = extract(path, head_text) if head_text is not None else None
    if head_extracted is None:
        return None
    head_header, head_exports = head_extracted
    if not head_header or head_header == "syntax-error" or header.strip() != head_header.strip():
        return None
    if exports == head_exports:
        return None

    added = sorted(exports - head_exports)
    removed = sorted(head_exports - exports)
    parts: list[str] = []
    if added:
        parts.append(f"added {', '.join(added[:5])}")
    if removed:
        parts.append(f"removed {', '.join(removed[:5])}")
    delta = "; ".join(parts)
    return (
        f"{raw}:1: public exports changed ({delta}) while the module header stayed identical to HEAD. "
        "Verify the module header still accurately describes this file's purpose and boundaries."
    )


def check_file(raw: str) -> str | None:
    path = Path(raw)
    if not path.is_file() or is_test_file(path):
        return None
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return None
    if not text.strip() or is_empty_init_py(path, text):
        return None

    extracted = extract(path, text)
    if extracted is None or extracted[0] == "syntax-error":
        return None
    header, exports = extracted
    if not header:
        return (
            f"{raw}:1: missing module header. "
            "Add a concise top-of-file docstring/comment explaining what this module owns and its boundaries."
        )
    return _check_export_drift(raw, path, header=header, exports=exports)


def main(argv: list[str]) -> int:
    findings = [msg for raw in argv if (msg := check_file(raw))]
    if findings:
        sys.stdout.write("\n".join(findings) + "\n")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
