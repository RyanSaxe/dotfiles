#!/usr/bin/env python3
"""Flag pure pass-through routing wrapper functions in Python and TypeScript/JS.

Just-in-time steering check (`gate: false`) for the BYOR `craft` package.
Detects functions or methods whose entire body only forwards parameters and
constants straight to another function (including the two-statement
`res = call(...); return res` shape), while skipping dunders, decorated
functions, overrides, and constructors.
"""

from __future__ import annotations

import ast
import re
import sys
from pathlib import Path

PY_EXTS = {".py", ".pyi"}
JS_EXTS = {".ts", ".tsx", ".mts", ".cts", ".js", ".jsx", ".mjs", ".cjs"}


def _is_trivial_py_arg(node: ast.AST, param_names: set[str]) -> bool:
    if isinstance(node, ast.Constant):
        return True
    if isinstance(node, ast.Name):
        return node.id in param_names
    if isinstance(node, ast.Starred):
        return _is_trivial_py_arg(node.value, param_names)
    if isinstance(node, ast.Attribute) and isinstance(node.value, ast.Name) and node.value.id in {"self", "cls"}:
        return True
    return False


def _is_super_call(call: ast.Call) -> bool:
    return (
        isinstance(call.func, ast.Attribute)
        and isinstance(call.func.value, ast.Call)
        and isinstance(call.func.value.func, ast.Name)
        and call.func.value.func.id == "super"
    )


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


def check_python(raw: str, text: str) -> list[str]:
    try:
        tree = ast.parse(text)
    except SyntaxError:
        return []

    findings: list[str] = []
    for node in ast.walk(tree):
        if not isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            continue
        if node.name.startswith("__") and node.name.endswith("__"):
            continue
        if node.decorator_list:
            continue

        body = list(node.body)
        if (
            body
            and isinstance(body[0], ast.Expr)
            and isinstance(body[0].value, ast.Constant)
            and isinstance(body[0].value.value, str)
        ):
            body = body[1:]

        call: ast.Call | None = None
        if len(body) == 1:
            stmt = body[0]
            if isinstance(stmt, ast.Return):
                call = _unwrap_call(stmt.value)
            elif isinstance(stmt, ast.Expr):
                call = _unwrap_call(stmt.value)
        elif len(body) == 2:
            first, second = body
            if (
                isinstance(first, ast.Assign)
                and len(first.targets) == 1
                and isinstance(first.targets[0], ast.Name)
                and isinstance(second, ast.Return)
                and isinstance(second.value, ast.Name)
                and first.targets[0].id == second.value.id
            ):
                call = _unwrap_call(first.value)

        if call is None or _is_super_call(call):
            continue
        target_name = _call_name(call)
        if not target_name or target_name == node.name or target_name.endswith(f".{node.name}"):
            continue

        params = _param_names(node.args)
        all_args_trivial = all(_is_trivial_py_arg(arg, params) for arg in call.args) and all(
            _is_trivial_py_arg(kw.value, params) for kw in call.keywords
        )
        if not all_args_trivial:
            continue

        findings.append(
            f"{raw}:{node.lineno}: pure routing wrapper `{node.name}` only forwards to `{target_name}`. "
            "Call the target directly unless this wrapper defines a real domain boundary."
        )
    return findings


JS_FUNC_RE = re.compile(
    r"^(?P<indent>[ \t]*)(?:export\s+(?:default\s+)?)?(?:async\s+)?function\s+(?P<name>[A-Za-z_$]\w*)\s*(?:<[^>]*>)?\s*\((?P<params>[^)]*)\)\s*(?::[^{=]+)?\{",
    re.MULTILINE,
)
JS_ARROW_BLOCK_RE = re.compile(
    r"^(?P<indent>[ \t]*)(?:export\s+)?const\s+(?P<name>[A-Za-z_$]\w*)\s*=\s*(?:async\s+)?(?:<[^>]*>)?\s*\((?P<params>[^)]*)\)\s*(?::[^=]+)?=>\s*\{",
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


def check_js(raw: str, text: str) -> list[str]:
    findings: list[str] = []
    for pattern in (JS_FUNC_RE, JS_ARROW_BLOCK_RE):
        for match in pattern.finditer(text):
            name = match.group("name")
            if name == "constructor":
                continue
            body = _extract_braced_body(text, match.end() - 1)
            if body is None:
                continue
            # Strip line comments and split statements.
            cleaned = re.sub(r"//[^\n]*", "", body)
            cleaned = re.sub(r"/\*.*?\*/", "", cleaned, flags=re.DOTALL)
            stmts = [s.strip() for s in cleaned.split(";") if s.strip()]
            target: str | None = None
            if len(stmts) == 1:
                stmt = stmts[0]
                if stmt.startswith("return "):
                    target = _is_trivial_js_call(stmt[7:], name)
                else:
                    target = _is_trivial_js_call(stmt, name)
            elif len(stmts) == 2:
                assign = re.match(r"^(?:const|let|var)\s+([A-Za-z_$]\w*)\s*=\s*(.+)$", stmts[0])
                ret = re.match(r"^return\s+([A-Za-z_$]\w*)$", stmts[1])
                if assign and ret and assign.group(1) == ret.group(1):
                    target = _is_trivial_js_call(assign.group(2), name)
            if target:
                line_no = text.count("\n", 0, match.start()) + 1
                findings.append(
                    f"{raw}:{line_no}: pure routing wrapper `{name}` only forwards to `{target}`. "
                    "Call the target directly unless this wrapper defines a real domain boundary."
                )
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
        if path.suffix in PY_EXTS:
            findings.extend(check_python(raw, text))
        elif path.suffix in JS_EXTS:
            findings.extend(check_js(raw, text))

    if findings:
        sys.stdout.write("\n".join(findings) + "\n")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
