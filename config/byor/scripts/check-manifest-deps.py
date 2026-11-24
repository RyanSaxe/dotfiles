#!/usr/bin/env python3
"""Warn when dependency sections change without updating the matching lockfile.

Just-in-time steering check (`gate: false`) for the BYOR `craft` package.
Inspects `pyproject.toml`, `package.json`, and `Cargo.toml` by parsing only
their dependency sections against `HEAD`, so routine metadata or tool-config
edits never fire false positives.
"""

from __future__ import annotations

import json
import subprocess
import sys
import tomllib
from pathlib import Path

MANIFEST_INFO: dict[str, tuple[str, str]] = {
    "pyproject.toml": ("uv.lock", "uv add"),
    "package.json": ("package-lock.json", "npm install"),
    "Cargo.toml": ("Cargo.lock", "cargo add"),
}


def extract_deps(name: str, text: str) -> object | None:
    try:
        if name == "package.json":
            data = json.loads(text)
            if not isinstance(data, dict):
                return None
            return {
                key: data.get(key)
                for key in ("dependencies", "devDependencies", "peerDependencies", "optionalDependencies")
            }
        data = tomllib.loads(text)
        if name == "pyproject.toml":
            project = data.get("project", {}) if isinstance(data.get("project"), dict) else {}
            uv_cfg = data.get("tool", {}).get("uv", {}) if isinstance(data.get("tool"), dict) else {}
            return {
                "dependencies": project.get("dependencies"),
                "optional-dependencies": project.get("optional-dependencies"),
                "dependency-groups": data.get("dependency-groups"),
                "uv-dev-dependencies": uv_cfg.get("dev-dependencies") if isinstance(uv_cfg, dict) else None,
            }
        if name == "Cargo.toml":
            workspace = data.get("workspace", {}) if isinstance(data.get("workspace"), dict) else {}
            return {
                "dependencies": data.get("dependencies"),
                "dev-dependencies": data.get("dev-dependencies"),
                "build-dependencies": data.get("build-dependencies"),
                "workspace-dependencies": workspace.get("dependencies"),
            }
    except (ValueError, tomllib.TOMLDecodeError):
        return None
    return None


def git_show_head(rel: str) -> str | None:
    result = subprocess.run(
        ["git", "show", f"HEAD:{rel}"],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
    )
    return result.stdout if result.returncode == 0 else None


def lockfile_was_updated(lockfile: Path) -> bool:
    result = subprocess.run(
        ["git", "status", "--porcelain", "--", str(lockfile)],
        capture_output=True,
        text=True,
        check=False,
    )
    return result.returncode == 0 and bool(result.stdout.strip())


def check_file(raw: str) -> str | None:
    path = Path(raw)
    if not path.is_file() or path.name not in MANIFEST_INFO:
        return None
    try:
        rel = path.resolve().relative_to(Path.cwd().resolve()).as_posix()
        current_text = path.read_text(encoding="utf-8", errors="replace")
    except (ValueError, OSError):
        return None

    head_text = git_show_head(rel)
    head_deps = extract_deps(path.name, head_text) if head_text is not None else None
    current_deps = extract_deps(path.name, current_text)
    if head_deps is None or current_deps is None or head_deps == current_deps:
        return None

    lock_name, add_cmd = MANIFEST_INFO[path.name]
    lock_path = path.parent / lock_name
    if not lock_path.is_file() or lockfile_was_updated(lock_path):
        return None

    return (
        f"{raw}: dependency entries changed while `{lock_name}` was not updated. "
        f"Confirm dependency changes with the user and run `{add_cmd}` so `{lock_name}` stays in sync."
    )


def main(argv: list[str]) -> int:
    findings = [msg for raw in argv if (msg := check_file(raw))]
    if findings:
        sys.stdout.write("\n".join(findings) + "\n")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
