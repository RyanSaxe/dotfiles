#!/usr/bin/env python3
"""Read-only post-edit linter runner for BYOR.

Runs only the linters and type checkers the current repository configures or
installs locally, strictly read-only (never formats or mutates files) and
bounded by a 5-second per-tool timeout so slow cold caches never stall an edit.
Rust `.rs` files are skipped here and checked by `cargo clippy` in prek and CI.
"""

from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path

TIMEOUT_SECONDS = 5
PYTHON_EXTS = {".py", ".pyi"}
WEB_EXTS = {".js", ".jsx", ".mjs", ".cjs", ".ts", ".tsx", ".mts", ".cts"}


def run_tool(argv: list[str], cwd: Path) -> str | None:
    """Run one linter command with a bounded timeout; return failure output or None."""
    try:
        result = subprocess.run(
            argv,
            cwd=cwd,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=TIMEOUT_SECONDS,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    if result.returncode == 0:
        return None
    parts = [part.strip() for part in (result.stdout, result.stderr) if part.strip()]
    return "\n".join(parts) if parts else f"{argv[0]} exited with status {result.returncode}"


def check_python(repo_root: Path, files: list[str]) -> list[str]:
    failures: list[str] = []
    ruff_bin = repo_root / ".venv" / "bin" / "ruff"
    if ruff_bin.is_file():
        out = run_tool([str(ruff_bin), "check", "--output-format", "concise", *files], repo_root)
        if out:
            failures.append(f"[ruff]\n{out}")

    ty_bin = repo_root / ".venv" / "bin" / "ty"
    if ty_bin.is_file():
        out = run_tool(
            [str(ty_bin), "check", "--output-format", "concise", "--no-progress", "--color", "never", *files],
            repo_root,
        )
        if out:
            failures.append(f"[ty]\n{out}")
    return failures


def check_web(repo_root: Path, files: list[str]) -> list[str]:
    oxlint_bin = repo_root / "node_modules" / ".bin" / "oxlint"
    if not oxlint_bin.is_file():
        return []
    argv = [str(oxlint_bin), "--deny-warnings"]
    has_tsgolint = (repo_root / "node_modules" / "oxlint-tsgolint").exists() or (
        repo_root / "node_modules" / ".bin" / "tsgolint"
    ).exists()
    if has_tsgolint and (repo_root / "tsconfig.json").is_file():
        argv.extend(["--type-aware", "--type-check"])
    argv.extend(files)
    out = run_tool(argv, repo_root)
    return [f"[oxlint]\n{out}"] if out else []


def check_markdown(repo_root: Path, files: list[str]) -> list[str]:
    if not ((repo_root / ".rumdl.toml").is_file() or (repo_root / "rumdl.toml").is_file()):
        return []
    rumdl = shutil.which("rumdl")
    if not rumdl:
        return []
    out = run_tool([rumdl, "check", *files], repo_root)
    return [f"[rumdl]\n{out}"] if out else []


def check_go(repo_root: Path, files: list[str]) -> list[str]:
    if not (repo_root / "go.mod").is_file():
        return []
    has_cfg = any(
        (repo_root / name).is_file() for name in (".golangci.yml", ".golangci.yaml", ".golangci.toml", ".golangci.json")
    )
    golangci = shutil.which("golangci-lint")
    if not (has_cfg and golangci):
        return []

    pkg_dirs: list[str] = []
    for raw in files:
        path = Path(raw).resolve()
        try:
            rel_parent = path.parent.relative_to(repo_root.resolve())
        except ValueError:
            continue
        pkg = "." if str(rel_parent) == "." else f"./{rel_parent.as_posix()}"
        if pkg not in pkg_dirs:
            pkg_dirs.append(pkg)
    if not pkg_dirs:
        return []
    out = run_tool([golangci, "run", *pkg_dirs], repo_root)
    return [f"[golangci-lint]\n{out}"] if out else []


def check_lua(repo_root: Path, files: list[str]) -> list[str]:
    if not ((repo_root / ".emmyrc.json").is_file() or (repo_root / "emmyrc.json").is_file()):
        return []
    emmy = shutil.which("emmylua_check")
    if not emmy:
        return []
    out = run_tool([emmy, *files], repo_root)
    return [f"[emmylua_check]\n{out}"] if out else []


def main(argv: list[str]) -> int:
    repo_root = Path.cwd()
    raw_files = [arg for arg in argv if Path(arg).is_file()]
    if not raw_files:
        return 0

    py_files = [f for f in raw_files if Path(f).suffix in PYTHON_EXTS]
    web_files = [f for f in raw_files if Path(f).suffix in WEB_EXTS]
    md_files = [f for f in raw_files if Path(f).suffix == ".md"]
    go_files = [f for f in raw_files if Path(f).suffix == ".go"]
    lua_files = [f for f in raw_files if Path(f).suffix == ".lua"]

    failures: list[str] = []
    if py_files:
        failures.extend(check_python(repo_root, py_files))
    if web_files:
        failures.extend(check_web(repo_root, web_files))
    if md_files:
        failures.extend(check_markdown(repo_root, md_files))
    if go_files:
        failures.extend(check_go(repo_root, go_files))
    if lua_files:
        failures.extend(check_lua(repo_root, lua_files))

    if failures:
        sys.stdout.write("\n\n".join(failures) + "\n")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
