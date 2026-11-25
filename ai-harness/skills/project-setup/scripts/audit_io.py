"""Read-only file, config, git, and dependency helpers for the repository audit."""

from __future__ import annotations

import configparser
import json
import os
import re
import shutil
import subprocess
import tomllib
from pathlib import Path
from typing import Any

JSONC_TOKEN_RE = re.compile(r'"(?:\\.|[^"\\])*"|//[^\n]*|/\*.*?\*/', re.DOTALL)
PRUNE_DIRS = frozenset({".git", "node_modules", ".venv", "venv", "target", "dist", "build", "vendor"}) | frozenset(
    {"__pycache__", ".mypy_cache", ".pytest_cache", ".ruff_cache", ".rumdl_cache", ".next", ".astro"}
)


def read_text(path: Path) -> str | None:
    try:
        return path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return None


def read_json(path: Path, *, jsonc: bool = False) -> dict[str, Any]:
    text = read_text(path)
    if text is None:
        return {}
    if jsonc:
        text = JSONC_TOKEN_RE.sub(lambda m: m.group(0) if m.group(0).startswith('"') else "", text)
    try:
        data = json.loads(text)
    except json.JSONDecodeError:
        return {}
    return data if isinstance(data, dict) else {}


def read_toml(path: Path) -> dict[str, Any]:
    try:
        with path.open("rb") as handle:
            data = tomllib.load(handle)
    except (OSError, tomllib.TOMLDecodeError):
        return {}
    return data if isinstance(data, dict) else {}


def as_dict(value: object) -> dict[str, Any]:
    if isinstance(value, dict):
        return value
    return {}


def is_fixture_path(rel: str) -> bool:
    parts = Path(rel).parts[:-1]
    return "fixtures" in parts


def is_template_or_fixture_path(rel: str) -> bool:
    parts = Path(rel).parts[:-1]
    return "fixtures" in parts or "templates" in parts


def _run_git(root: Path, *args: str) -> subprocess.CompletedProcess[bytes] | None:
    git_bin = shutil.which("git")
    if git_bin is None:
        return None
    try:
        # Fixed read-only git invocation against a validated directory path.
        return subprocess.run([git_bin, "-C", str(root), *args], capture_output=True, check=False)
    except OSError:
        return None


def list_repo_files(root: Path) -> tuple[list[str], bool]:
    probe = _run_git(root, "rev-parse", "--is-inside-work-tree")
    if probe is not None and probe.returncode == 0 and probe.stdout.strip() == b"true":
        listed = _run_git(root, "ls-files", "-z", "--cached", "--others", "--exclude-standard")
        if listed is not None and listed.returncode == 0:
            raw_entries = [
                item.decode("utf-8", errors="surrogateescape") for item in listed.stdout.split(b"\0") if item
            ]
            existing = [rel for rel in raw_entries if (root / rel).is_file()]
            return sorted(set(existing)), True

    collected: list[str] = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = sorted(name for name in dirnames if name not in PRUNE_DIRS)
        base = Path(dirpath)
        collected.extend(
            (base / name).relative_to(root).as_posix() for name in sorted(filenames) if (base / name).is_file()
        )
    return collected, False


def normalize_pkg(spec: str) -> str:
    match = re.match(r"^\s*([A-Za-z0-9_.-]+)", spec)
    return match.group(1).lower().replace("_", "-") if match else ""


def deps_from_str_list(items: object) -> set[str]:
    if not isinstance(items, list):
        return set()
    return {name for item in items if isinstance(item, str) and (name := normalize_pkg(item))}


def _deps_from_poetry(pyproject: dict[str, Any]) -> set[str]:
    poetry = as_dict(as_dict(pyproject.get("tool")).get("poetry"))
    deps: set[str] = set()
    for key in ("dependencies", "dev-dependencies"):
        deps.update(name.lower().replace("_", "-") for name in as_dict(poetry.get(key)))
    for group in as_dict(poetry.get("group")).values():
        deps.update(name.lower().replace("_", "-") for name in as_dict(as_dict(group).get("dependencies")))
    return deps


def _deps_from_requirements(root: Path) -> set[str]:
    deps: set[str] = set()
    for req_file in sorted(root.glob("requirements*.txt")):
        text = read_text(req_file) or ""
        for raw_line in text.splitlines():
            line = raw_line.split("#", 1)[0].strip()
            if line and not line.startswith("-") and (name := normalize_pkg(line)):
                deps.add(name)
    return deps


def collect_python_deps(root: Path, pyproject: dict[str, Any]) -> set[str]:
    project = as_dict(pyproject.get("project"))
    deps = deps_from_str_list(project.get("dependencies"))
    for group in as_dict(project.get("optional-dependencies")).values():
        deps.update(deps_from_str_list(group))
    for group in as_dict(pyproject.get("dependency-groups")).values():
        deps.update(deps_from_str_list(group))
    deps.update(_deps_from_poetry(pyproject))
    deps.update(_deps_from_requirements(root))
    return deps


def collect_node_deps(package_json: dict[str, Any]) -> set[str]:
    deps: set[str] = set()
    for key in ("dependencies", "devDependencies", "peerDependencies", "optionalDependencies"):
        deps.update(str(name) for name in as_dict(package_json.get(key)))
    return deps


def read_ini_sections(root: Path) -> dict[str, set[str]]:
    sections: dict[str, set[str]] = {}
    for ini_name in ("setup.cfg", "tox.ini"):
        ini_path = root / ini_name
        if not ini_path.is_file():
            continue
        parser = configparser.ConfigParser()
        try:
            parser.read(ini_path, encoding="utf-8")
            sections[ini_name] = set(parser.sections())
        except (configparser.Error, OSError):
            sections[ini_name] = set()
    return sections


def _parse_yaml_list_block(lines: list[str]) -> list[str]:
    values: list[str] = []
    for sub in lines:
        stripped = sub.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if not sub.startswith((" ", "\t")):
            break
        if stripped.startswith("- "):
            values.append(stripped[2:].strip().strip("\"'"))
    return values


def parse_simple_yaml_list(text: str, key: str) -> list[str]:
    lines = text.splitlines()
    pattern = re.compile(rf"^{re.escape(key)}\s*:")
    for idx, raw_line in enumerate(lines):
        if not pattern.match(raw_line):
            continue
        remainder = raw_line.split(":", 1)[1].strip()
        if remainder.startswith("[") and remainder.endswith("]"):
            inner = remainder[1:-1].strip()
            return [item.strip().strip("\"'") for item in inner.split(",") if item.strip()] if inner else []
        if remainder:
            return [remainder.strip("\"'")]
        return _parse_yaml_list_block(lines[idx + 1 :])
    return []


def parse_simple_yaml_bool(text: str, key: str) -> bool | None:
    pattern = re.compile(rf"^{re.escape(key)}\s*:")
    for raw_line in text.splitlines():
        if pattern.match(raw_line):
            val = raw_line.split(":", 1)[1].split("#", 1)[0].strip().lower()
            if val in {"true", "false"}:
                return val == "true"
    return None
