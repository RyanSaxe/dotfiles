#!/usr/bin/env -S uv run -q --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///

"""Validate the authored AI harness without invoking an agent CLI."""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path
from typing import TypeAlias

import tomllib

REPO_ROOT = Path(__file__).resolve().parent.parent
HARNESS_ROOT = REPO_ROOT / "ai-harness"
JsonValue: TypeAlias = (
    str | int | float | bool | None | list["JsonValue"] | dict[str, "JsonValue"]
)
SKILL_VALIDATOR = (
    "uvx",
    "--from",
    "skills-ref==0.1.1",
    "agentskills",
    "validate",
)


class HarnessError(Exception):
    """A violated AI harness ownership or structure contract."""


def read_json(path: Path) -> dict[str, JsonValue]:
    value = json.loads(path.read_text())
    if not isinstance(value, dict) or not all(isinstance(key, str) for key in value):
        raise HarnessError(f"{path.relative_to(REPO_ROOT)} must contain a JSON object")
    return value


def require_string(mapping: dict[str, JsonValue], key: str, path: Path) -> str:
    value = mapping.get(key)
    if not isinstance(value, str) or not value.strip():
        raise HarnessError(
            f"{path.relative_to(REPO_ROOT)} requires a non-empty {key!r}"
        )
    return value


def validate_manifests() -> None:
    for path in (
        HARNESS_ROOT / ".claude-plugin/plugin.json",
        HARNESS_ROOT / "plugin.json",
    ):
        manifest = read_json(path)
        if require_string(manifest, "name", path) != "dotfiles":
            raise HarnessError(
                f"{path.relative_to(REPO_ROOT)} must use plugin name 'dotfiles'"
            )

        for field in ("agents", "hooks", "mcpServers", "lspServers", "skills"):
            raw_paths = manifest.get(field)
            if raw_paths is None or isinstance(raw_paths, dict):
                continue
            paths = [raw_paths] if isinstance(raw_paths, str) else raw_paths
            if not isinstance(paths, list) or not all(
                isinstance(item, str) for item in paths
            ):
                raise HarnessError(
                    f"{path.relative_to(REPO_ROOT)} has invalid {field!r} paths"
                )
            for relative_path in paths:
                candidate = HARNESS_ROOT / relative_path
                if not candidate.exists():
                    raise HarnessError(
                        f"{path.relative_to(REPO_ROOT)} references missing {relative_path!r}"
                    )


def validate_skills() -> None:
    skill_dirs = sorted(
        path for path in (HARNESS_ROOT / "skills").iterdir() if path.is_dir()
    )

    for skill_dir in skill_dirs:
        command = (*SKILL_VALIDATOR, str(skill_dir))
        result = subprocess.run(command, capture_output=True, check=False, text=True)
        if result.returncode:
            details = result.stderr.strip() or result.stdout.strip()
            raise HarnessError(f"{skill_dir.relative_to(REPO_ROOT)}: {details}")


def validate_settings() -> None:
    read_json(HARNESS_ROOT / "claude/settings.json")
    read_json(HARNESS_ROOT / "copilot/settings.json")

    codex_path = HARNESS_ROOT / "codex/config.toml"
    config = tomllib.loads(codex_path.read_text())
    if "projects" in config:
        raise HarnessError(
            f"{codex_path.relative_to(REPO_ROOT)} contains project state"
        )

    hooks = config.get("hooks")
    if isinstance(hooks, dict) and "state" in hooks:
        raise HarnessError(f"{codex_path.relative_to(REPO_ROOT)} contains hook state")

    tui = config.get("tui")
    if isinstance(tui, dict) and "model_availability_nux" in tui:
        raise HarnessError(f"{codex_path.relative_to(REPO_ROOT)} contains UI state")


def main() -> int:
    checks = (
        validate_manifests,
        validate_skills,
        validate_settings,
    )
    try:
        for check in checks:
            check()
    except (HarnessError, json.JSONDecodeError, tomllib.TOMLDecodeError) as error:
        print(f"ai-harness-check: {error}", file=sys.stderr)
        return 1

    print(f"ai-harness-check: ok ({len(checks)} contracts)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
