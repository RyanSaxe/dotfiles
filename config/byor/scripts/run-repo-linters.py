#!/usr/bin/env python3
"""Read-only post-edit linter runner for BYOR.

Runs only the linters and type checkers the current repository configures or
installs locally, strictly read-only (never formats or mutates files) and
bounded by a 5-second per-tool timeout so slow cold caches never stall an edit.
Rust `.rs` files are skipped here and checked by `cargo clippy` in prek and CI.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
from pathlib import Path

TIMEOUT_SECONDS = 5
PYTHON_EXTS = {".py", ".pyi"}
WEB_EXTS = {".js", ".jsx", ".mjs", ".cjs", ".ts", ".tsx", ".mts", ".cts"}
SHELL_EXTS = {".sh", ".bash"}
NIX_EXTS = {".nix"}
MD_EXTS = {".md"}
GO_EXTS = {".go"}
LUA_EXTS = {".lua"}


def run_tool(argv: list[str], cwd: Path, *, env: dict[str, str] | None = None) -> str | None:
    """Run one linter command with a bounded timeout; return failure output or None."""
    try:
        result = subprocess.run(
            argv,
            cwd=cwd,
            env=env,
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


def _emmy_env(emmy_cfg: Path) -> dict[str, str] | None:
    if "VIMRUNTIME" in os.environ:
        return None
    try:
        if "VIMRUNTIME" not in emmy_cfg.read_text(encoding="utf-8", errors="replace"):
            return None
    except OSError:
        return None
    nvim = shutil.which("nvim")
    if not nvim:
        return None
    try:
        result = subprocess.run(
            [nvim, "--clean", "--headless", "-u", "NONE", '+lua io.write(vim.env.VIMRUNTIME or "")', "+q"],
            capture_output=True,
            text=True,
            timeout=2,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    vimruntime = result.stdout.strip()
    return {**os.environ, "VIMRUNTIME": vimruntime} if result.returncode == 0 and vimruntime else None


def check_lua(repo_root: Path, files: list[str]) -> list[str]:
    failures: list[str] = []
    emmy_cfg = next(
        (repo_root / name for name in (".emmyrc.json", "emmyrc.json") if (repo_root / name).is_file()), None
    )
    if emmy_cfg is not None:
        emmy = shutil.which("emmylua_check")
        if emmy:
            out = run_tool(
                [emmy, "-c", str(emmy_cfg), "--severity", "error", *files],
                repo_root,
                env=_emmy_env(emmy_cfg),
            )
            if out:
                failures.append(f"[emmylua_check]\n{out}")

    luacheck = shutil.which("luacheck")
    if luacheck:
        out = run_tool(
            [luacheck, "--no-config", "--only", "561", "--max-cyclomatic-complexity", "10", *files], repo_root
        )
        if out:
            failures.append(f"[luacheck]\n{out}")
    return failures


def _has_sh_or_bash_shebang(file_path: str) -> bool:
    try:
        with Path(file_path).open(encoding="utf-8", errors="replace") as handle:
            first_line = handle.readline().strip()
    except OSError:
        return False
    if not first_line.startswith("#!"):
        return False
    tokens = first_line[2:].split()
    if not tokens:
        return False
    shell_name = Path(tokens[-1] if Path(tokens[0]).name == "env" and len(tokens) > 1 else tokens[0]).name
    return shell_name in {"sh", "bash", "dash"}


def check_shell(repo_root: Path, files: list[str]) -> list[str]:
    shellcheck = shutil.which("shellcheck")
    if not shellcheck:
        return []
    targets = [file_path for file_path in files if _has_sh_or_bash_shebang(file_path)]
    if not targets:
        return []
    out = run_tool([shellcheck, *targets], repo_root)
    return [f"[shellcheck]\n{out}"] if out else []


def check_nix(repo_root: Path, files: list[str]) -> list[str]:
    failures: list[str] = []
    deadnix = shutil.which("deadnix")
    if deadnix:
        out = run_tool([deadnix, "--fail", *files], repo_root)
        if out:
            failures.append(f"[deadnix]\n{out}")

    statix = shutil.which("statix")
    if statix:
        statix_outputs = [out for file_path in files if (out := run_tool([statix, "check", file_path], repo_root))]
        if statix_outputs:
            failures.append("[statix]\n" + "\n".join(statix_outputs))
    return failures


CHECKERS = (
    (PYTHON_EXTS, check_python),
    (WEB_EXTS, check_web),
    (MD_EXTS, check_markdown),
    (GO_EXTS, check_go),
    (LUA_EXTS, check_lua),
    (SHELL_EXTS, check_shell),
    (NIX_EXTS, check_nix),
)


def main(argv: list[str]) -> int:
    repo_root = Path.cwd()
    raw_files = [arg for arg in argv if Path(arg).is_file()]
    if not raw_files:
        return 0

    failures: list[str] = []
    for exts, checker in CHECKERS:
        matched = [f for f in raw_files if Path(f).suffix in exts]
        if matched:
            failures.extend(checker(repo_root, matched))

    if failures:
        sys.stdout.write("\n\n".join(failures) + "\n")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
