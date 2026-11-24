#!/usr/bin/env python3
"""Flag pure routing wrappers and nudge on newly written one-statement helpers.

Just-in-time steering check (`gate: false`) for the BYOR `craft` package,
covering Python and TypeScript/JavaScript in two tiers:
1. `[error]` Pure pass-through wrappers anywhere in the edited file whose body
   only forwards parameters, constants, or `self`/`this` attributes to another
   call (including `res = call(...); return res`).
2. `[nudge]` Newly added or modified one-statement functions in non-test source
   files (diff-scoped against `HEAD`), prompting the agent to inline shallow
   helpers (even across 2-3 call sites) to keep call stacks flat and grep clear.
"""

from __future__ import annotations

import ast
import re
import subprocess
import sys
from pathlib import Path

PY_EXTS = {".py", ".pyi"}
JS_EXTS = {".ts", ".tsx", ".mts", ".cts", ".js", ".jsx", ".mjs", ".cjs"}
TEST_DIRS = {"tests", "test", "__tests__", "spec", "specs"}
HUNK_RE = re.compile(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@")


def _is_test_file(path: Path) -> bool:
    if {part.lower() for part in path.parts[:-1]} & TEST_DIRS:
        return True
    name = path.name.lower()
    if name == "conftest.py" or name.startswith("test_") or name.endswith("_test.py"):
        return True
    return any(marker in name for marker in (".test.", ".spec."))


def _added_line_numbers(path: Path) -> set[int] | None:
    """Return 1-based line numbers added vs HEAD, or None if the file is new/untracked."""
    try:
        rel = path.resolve().relative_to(Path.cwd().resolve()).as_posix()
    except ValueError:
        return None
    tracked = subprocess.run(["git", "cat-file", "-e", f"HEAD:{rel}"], capture_output=True, check=False)
    if tracked.returncode != 0:
        return None
    diff = subprocess.run(
        ["git", "diff", "HEAD", "-U0", "--", rel],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
    )
    if diff.returncode != 0:
        return set()

    added: set[int] = set()
    current_line = 0
    for line in diff.stdout.splitlines():
        hunk = HUNK_RE.match(line)
        if hunk:
            current_line = int(hunk.group(1))
            continue
        if line.startswith(("+++", "---")):
            continue
        if line.startswith("+"):
            added.add(current_line)
            current_line += 1
        elif not line.startswith("-"):
            current_line += 1
    return added


def _line_is_new(line_no: int, added_lines: set[int] | None) -> bool:
    return added_lines is None or line_no in added_lines


TWO_STMT_WRAPPER_LEN = 2


def _is_trivial_py_arg(node: ast.AST, param_names: set[str]) -> bool:
    if isinstance(node, ast.Constant):
        return True
    if isinstance(node, ast.Name):
        return node.id in param_names
    if isinstance(node, ast.Starred):
        return _is_trivial_py_arg(node.value, param_names)
    return isinstance(node, ast.Attribute) and isinstance(node.value, ast.Name) and node.value.id in {"self", "cls"}


def _is_super_call(call: ast.Call) -> bool:
    return (
        isinstance(call.func, ast.Attribute)
        and isinstance(call.func.value, ast.Call)
        and isinstance(call.func.value.func, ast.Name)
        and call.func.value.func.id == "super"
    )


def _is_py_stub(stmt: ast.stmt) -> bool:
    if isinstance(stmt, ast.Pass):
        return True
    if isinstance(stmt, ast.Expr) and isinstance(stmt.value, ast.Constant) and stmt.value.value is Ellipsis:
        return True
    if isinstance(stmt, ast.Raise):
        exc = stmt.exc
        if isinstance(exc, ast.Name) and exc.id == "NotImplementedError":
            return True
        if isinstance(exc, ast.Call) and isinstance(exc.func, ast.Name) and exc.func.id == "NotImplementedError":
            return True
    return False


def _call_name(call: ast.Call) -> str | None:
    if isinstance(call.func, ast.Name):
        return call.func.id
    if isinstance(call.func, ast.Attribute):
        parts: list[str] = [call.func.attr]
        cur: ast.AST = call.func.value
        while isinstance(cur, ast.Attribute):
            parts.append(cur.attr)
            cur = cur.value
        if isinstance(cur, ast.Name):
            parts.append(cur.id)
            return ".".join(reversed(parts))
    return None


def _unwrap_call(expr: ast.AST | None) -> ast.Call | None:
    if isinstance(expr, ast.Await):
        expr = expr.value
    return expr if isinstance(expr, ast.Call) else None


def _param_names(args: ast.arguments) -> set[str]:
    names: set[str] = set()
    for arg in (*args.posonlyargs, *args.args, *args.kwonlyargs):
        names.add(arg.arg)
    if args.vararg:
        names.add(args.vararg.arg)
    if args.kwarg:
        names.add(args.kwarg.arg)
    return names


def _wrapper_error(raw: str, line_no: int, *, name: str, target: str) -> str:
    return (
        f"{raw}:{line_no}: [error] `{name}` only forwards to `{target}`. "
        f"Call `{target}` directly unless `{name}` marks a real module boundary."
    )


def _shallow_nudge(raw: str, line_no: int, *, name: str) -> str:
    return (
        f"{raw}:{line_no}: [nudge] `{name}` is a new one-statement function. "
        "Inline it at call sites (even across two or three callers) to keep call stacks flat and grep results clear, "
        "unless it owns a domain rule shared across the codebase."
    )


def _strip_docstring(body: list[ast.stmt]) -> list[ast.stmt]:
    if (
        body
        and isinstance(body[0], ast.Expr)
        and isinstance(body[0].value, ast.Constant)
        and isinstance(body[0].value.value, str)
    ):
        return body[1:]
    return body


def _extract_py_forwarding_call(body: list[ast.stmt]) -> ast.Call | None:
    if len(body) == 1 and isinstance(body[0], (ast.Return, ast.Expr)):
        return _unwrap_call(body[0].value)
    if len(body) == TWO_STMT_WRAPPER_LEN:
        first, second = body
        if (
            isinstance(first, ast.Assign)
            and len(first.targets) == 1
            and isinstance(first.targets[0], ast.Name)
            and isinstance(second, ast.Return)
            and isinstance(second.value, ast.Name)
            and first.targets[0].id == second.value.id
        ):
            return _unwrap_call(first.value)
    return None


def _check_py_function(
    raw: str,
    node: ast.FunctionDef | ast.AsyncFunctionDef,
    *,
    added_lines: set[int] | None,
    check_shallow: bool,
) -> str | None:
    if (node.name.startswith("__") and node.name.endswith("__")) or node.decorator_list:
        return None
    body = _strip_docstring(list(node.body))
    if not body or (len(body) == 1 and _is_py_stub(body[0])):
        return None

    call = _extract_py_forwarding_call(body)
    if call is not None and _is_super_call(call):
        return None

    if call is not None:
        target_name = _call_name(call)
        params = _param_names(node.args)
        is_distinct = bool(target_name and target_name != node.name and not target_name.endswith(f".{node.name}"))
        all_trivial = all(_is_trivial_py_arg(arg, params) for arg in call.args) and all(
            _is_trivial_py_arg(kw.value, params) for kw in call.keywords
        )
        if is_distinct and target_name and all_trivial:
            return _wrapper_error(raw, node.lineno, name=node.name, target=target_name)

    if (
        check_shallow
        and len(body) == 1
        and isinstance(body[0], (ast.Return, ast.Expr))
        and _line_is_new(node.lineno, added_lines)
    ):
        return _shallow_nudge(raw, node.lineno, name=node.name)
    return None


def check_python(raw: str, text: str, *, added_lines: set[int] | None, check_shallow: bool) -> list[str]:
    try:
        tree = ast.parse(text)
    except SyntaxError:
        return []

    findings: list[str] = []
    for node in ast.walk(tree):
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            msg = _check_py_function(raw, node, added_lines=added_lines, check_shallow=check_shallow)
            if msg:
                findings.append(msg)
    return findings


JS_FUNC_RE = re.compile(
    r"^(?P<indent>[ \t]*)(?:export\s+(?:default\s+)?)?(?:async\s+)?function\s+"
    r"(?P<name>[A-Za-z_$]\w*)\s*(?:<[^>]*>)?\s*\((?P<params>[^)]*)\)\s*(?::[^{=]+)?\{",
    re.MULTILINE,
)
JS_ARROW_BLOCK_RE = re.compile(
    r"^(?P<indent>[ \t]*)(?:export\s+)?const\s+(?P<name>[A-Za-z_$]\w*)\s*=\s*"
    r"(?:async\s+)?(?:<[^>]*>)?\s*\((?P<params>[^)]*)\)\s*(?::[^=]+)?=>\s*\{",
    re.MULTILINE,
)
JS_ARROW_EXPR_RE = re.compile(
    r"^(?P<indent>[ \t]*)(?:export\s+)?const\s+(?P<name>[A-Za-z_$]\w*)\s*=\s*"
    r"(?:async\s+)?(?:<[^>]*>)?\s*\((?P<params>[^)]*)\)\s*(?::[^=]+)?=>\s*(?!\{)(?P<expr>[^\n;]+);?",
    re.MULTILINE,
)
JS_SIMPLE_ARG_RE = re.compile(
    r"^(?:\.\.\.)?(?:this\.)?[A-Za-z_$][\w$]*$|^['\"][^'\"]*['\"]$|^-?\d+(?:\.\d+)?$|^(?:true|false|null|undefined)$"
)
JS_CALL_RE = re.compile(r"^(?:await\s+)?(?P<target>[A-Za-z_$][\w$.]*)\((?P<args>[^()]*)\)$")


def _extract_braced_body(text: str, open_brace_idx: int) -> str | None:
    depth = 0
    in_str: str | None = None
    escape = False
    for idx in range(open_brace_idx, len(text)):
        ch = text[idx]
        if in_str:
            if escape:
                escape = False
            elif ch == "\\":
                escape = True
            elif ch == in_str:
                in_str = None
            continue
        if ch in {"'", '"', "`"}:
            in_str = ch
            continue
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                return text[open_brace_idx + 1 : idx]
    return None


def _is_trivial_js_call(expr: str, func_name: str) -> str | None:
    match = JS_CALL_RE.match(expr.strip())
    if not match:
        return None
    target = match.group("target")
    if target == func_name or target.endswith(f".{func_name}") or target.startswith("super."):
        return None
    raw_args = match.group("args").strip()
    if raw_args:
        for arg in raw_args.split(","):
            if not JS_SIMPLE_ARG_RE.match(arg.strip()):
                return None
    return target


def _extract_js_block_target(stmts: list[str], name: str) -> str | None:
    if len(stmts) == 1:
        stmt = stmts[0]
        if "super." in stmt:
            return None
        return _is_trivial_js_call(stmt.removeprefix("return "), name)
    if len(stmts) == TWO_STMT_WRAPPER_LEN:
        assign = re.match(r"^(?:const|let|var)\s+([A-Za-z_$]\w*)\s*=\s*(.+)$", stmts[0])
        ret = re.match(r"^return\s+([A-Za-z_$]\w*)$", stmts[1])
        if assign and ret and assign.group(1) == ret.group(1):
            return _is_trivial_js_call(assign.group(2), name)
    return None


def _check_js_block(
    raw: str,
    body: str,
    *,
    name: str,
    line_no: int,
    added_lines: set[int] | None,
    check_shallow: bool,
) -> str | None:
    cleaned = re.sub(r"//[^\n]*", "", body)
    cleaned = re.sub(r"/\*.*?\*/", "", cleaned, flags=re.DOTALL)
    stmts = [s.strip() for s in cleaned.split(";") if s.strip()]
    if len(stmts) == 1 and "super." in stmts[0]:
        return None
    target = _extract_js_block_target(stmts, name)
    if target:
        return _wrapper_error(raw, line_no, name=name, target=target)
    if (
        check_shallow
        and len(stmts) == 1
        and not re.match(r"^(?:if|for|while|switch|try)\b", stmts[0])
        and _line_is_new(line_no, added_lines)
    ):
        return _shallow_nudge(raw, line_no, name=name)
    return None


def check_js(raw: str, text: str, *, added_lines: set[int] | None, check_shallow: bool) -> list[str]:
    findings: list[str] = []
    for pattern in (JS_FUNC_RE, JS_ARROW_BLOCK_RE):
        for match in pattern.finditer(text):
            name = match.group("name")
            if name == "constructor":
                continue
            body = _extract_braced_body(text, match.end() - 1)
            if body is None:
                continue
            line_no = text.count("\n", 0, match.start()) + 1
            msg = _check_js_block(
                raw, body, name=name, line_no=line_no, added_lines=added_lines, check_shallow=check_shallow
            )
            if msg:
                findings.append(msg)

    for match in JS_ARROW_EXPR_RE.finditer(text):
        name = match.group("name")
        expr = match.group("expr").strip()
        line_no = text.count("\n", 0, match.start()) + 1
        target = _is_trivial_js_call(expr, name)
        if target:
            findings.append(_wrapper_error(raw, line_no, name=name, target=target))
        elif check_shallow and _line_is_new(line_no, added_lines):
            findings.append(_shallow_nudge(raw, line_no, name=name))

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
        check_shallow = not _is_test_file(path)
        added_lines = _added_line_numbers(path) if check_shallow else set()
        if path.suffix in PY_EXTS:
            findings.extend(check_python(raw, text, added_lines=added_lines, check_shallow=check_shallow))
        elif path.suffix in JS_EXTS:
            findings.extend(check_js(raw, text, added_lines=added_lines, check_shallow=check_shallow))

    if findings:
        sys.stdout.write("\n".join(findings) + "\n")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
