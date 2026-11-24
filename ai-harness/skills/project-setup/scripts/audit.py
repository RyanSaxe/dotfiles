#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# dependencies = []
# ///
"""Read-only repository audit for the project-setup skill."""

from __future__ import annotations

import argparse
import configparser
import json
import os
import re
import shutil
import subprocess
import sys
import tomllib
from pathlib import Path
from typing import Any

WARNING_LINE_THRESHOLD = 600
HARD_CAP_LINE_THRESHOLD = 1000
EXPECTED_MAX_POSITIONAL_ARGS = 2

PRUNE_DIRS = frozenset(
    [
        ".git",
        "node_modules",
        ".venv",
        "venv",
        "target",
        "dist",
        "build",
        "__pycache__",
        ".mypy_cache",
        ".pytest_cache",
        ".ruff_cache",
        ".rumdl_cache",
        ".next",
        ".astro",
        "vendor",
    ],
)

SKIP_SIZE_EXTS = frozenset(
    [
        ".lock",
        ".svg",
        ".json",
        ".jsonc",
        ".csv",
        ".tsv",
        ".jsonl",
        ".ndjson",
        ".sql",
        ".xml",
        ".md",
        ".mdx",
        ".markdown",
        ".map",
        ".snap",
        ".po",
        ".pot",
        ".png",
        ".jpg",
        ".jpeg",
        ".gif",
        ".webp",
        ".ico",
        ".pdf",
        ".woff",
        ".woff2",
        ".ttf",
        ".otf",
        ".eot",
        ".mp4",
        ".webm",
        ".mov",
        ".zip",
        ".tar",
        ".gz",
        ".wasm",
        ".pyc",
        ".so",
        ".dylib",
        ".dll",
        ".exe",
    ],
)

SKIP_SIZE_RE = re.compile(
    r"(^|/)([^/]+-lock\.[^/]+|[^/]+\.(min|generated|gen)\.[^/]+|[^/]+_pb2\.py|[^/]+\.pb\.go)$",
)

STACK_EXTS: dict[str, frozenset[str]] = {
    "python": frozenset({".py", ".pyi"}),
    "web": frozenset(
        {
            ".ts",
            ".tsx",
            ".mts",
            ".cts",
            ".js",
            ".jsx",
            ".mjs",
            ".cjs",
            ".astro",
            ".svelte",
            ".vue",
            ".css",
            ".html",
        }
    ),
    "markdown": frozenset({".md", ".mdx", ".markdown"}),
    "rust": frozenset({".rs"}),
    "go": frozenset({".go"}),
    "lua": frozenset({".lua"}),
    "notebooks": frozenset({".ipynb"}),
}

TS_EXTS = frozenset({".ts", ".tsx", ".mts", ".cts"})
REACT_EXTS = frozenset({".jsx", ".tsx"})

WORKFLOW_LEGACY_PATTERNS: tuple[tuple[str, re.Pattern[str]], ...] = (
    ("pre-commit", re.compile(r"pre-commit/action|\bpre-commit\s+run\b")),
    ("prettier", re.compile(r"\bprettier\b")),
    ("eslint", re.compile(r"\beslint\b")),
    ("markdownlint", re.compile(r"\bmarkdownlint\b")),
    ("black", re.compile(r"\bblack\b")),
    ("isort", re.compile(r"\bisort\b")),
    ("flake8", re.compile(r"\bflake8\b")),
    ("pylint", re.compile(r"\bpylint\b")),
    ("mypy", re.compile(r"\bmypy\b")),
    ("pyright", re.compile(r"\bpyright\b")),
    ("biome", re.compile(r"\bbiome\b")),
    ("luacheck", re.compile(r"\bluacheck\b")),
    ("husky", re.compile(r"\bhusky\b")),
)

NON_CI_WORKFLOW_STEMS = frozenset(
    {
        "release",
        "publish",
        "deploy",
        "pages",
        "docs",
        "codeql",
        "stale",
        "labeler",
    }
)


def _read_text(path: Path) -> str | None:
    try:
        return path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return None


def _read_json(path: Path) -> dict[str, Any]:
    text = _read_text(path)
    if text is None:
        return {}
    try:
        data = json.loads(text)
    except json.JSONDecodeError:
        return {}
    return data if isinstance(data, dict) else {}


def _read_toml(path: Path) -> dict[str, Any]:
    try:
        with path.open("rb") as handle:
            data = tomllib.load(handle)
    except (OSError, tomllib.TOMLDecodeError):
        return {}
    return data if isinstance(data, dict) else {}


def _as_dict(value: object) -> dict[str, Any]:
    return value if isinstance(value, dict) else {}


def _run_git(root: Path, *args: str) -> subprocess.CompletedProcess[bytes] | None:
    git_bin = shutil.which("git")
    if git_bin is None:
        return None
    try:
        # Fixed read-only git invocation against a validated directory path.
        return subprocess.run([git_bin, "-C", str(root), *args], capture_output=True, check=False)  # noqa: S603
    except OSError:
        return None


def _list_repo_files(root: Path) -> tuple[list[str], bool]:
    """Return repo-relative POSIX file paths and whether root is a git repo."""
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


def _normalize_pkg(spec: str) -> str:
    match = re.match(r"^\s*([A-Za-z0-9_.-]+)", spec)
    return match.group(1).lower().replace("_", "-") if match else ""


def _deps_from_str_list(items: object) -> set[str]:
    if not isinstance(items, list):
        return set()
    return {name for item in items if isinstance(item, str) and (name := _normalize_pkg(item))}


def _deps_from_poetry(pyproject: dict[str, Any]) -> set[str]:
    poetry = _as_dict(_as_dict(pyproject.get("tool")).get("poetry"))
    deps: set[str] = set()
    for key in ("dependencies", "dev-dependencies"):
        deps.update(name.lower().replace("_", "-") for name in _as_dict(poetry.get(key)))
    for group in _as_dict(poetry.get("group")).values():
        deps.update(name.lower().replace("_", "-") for name in _as_dict(_as_dict(group).get("dependencies")))
    return deps


def _deps_from_requirements(root: Path) -> set[str]:
    deps: set[str] = set()
    for req_file in sorted(root.glob("requirements*.txt")):
        text = _read_text(req_file) or ""
        for raw_line in text.splitlines():
            line = raw_line.split("#", 1)[0].strip()
            if line and not line.startswith("-") and (name := _normalize_pkg(line)):
                deps.add(name)
    return deps


def _collect_python_deps(root: Path, pyproject: dict[str, Any]) -> set[str]:
    project = _as_dict(pyproject.get("project"))
    deps = _deps_from_str_list(project.get("dependencies"))
    for group in _as_dict(project.get("optional-dependencies")).values():
        deps.update(_deps_from_str_list(group))
    for group in _as_dict(pyproject.get("dependency-groups")).values():
        deps.update(_deps_from_str_list(group))
    deps.update(_deps_from_poetry(pyproject))
    deps.update(_deps_from_requirements(root))
    return deps


def _collect_node_deps(package_json: dict[str, Any]) -> set[str]:
    deps: set[str] = set()
    for key in ("dependencies", "devDependencies", "peerDependencies", "optionalDependencies"):
        deps.update(str(name) for name in _as_dict(package_json.get(key)))
    return deps


def _detect_stacks(root: Path, files: list[str], *, package_json: dict[str, Any]) -> dict[str, Any]:
    counts: dict[str, int] = dict.fromkeys(STACK_EXTS, 0)
    ts_count = 0
    react_count = 0
    for rel in files:
        ext = Path(rel).suffix.lower()
        for stack, exts in STACK_EXTS.items():
            if ext in exts:
                counts[stack] += 1
        ts_count += int(ext in TS_EXTS)
        react_count += int(ext in REACT_EXTS)

    node_deps = _collect_node_deps(package_json)
    has_python_marker = (
        (root / "pyproject.toml").is_file() or (root / "setup.py").is_file() or any(root.glob("requirements*.txt"))
    )
    markers = {
        "python": has_python_marker,
        "web": (root / "package.json").is_file(),
        "markdown": False,
        "rust": (root / "Cargo.toml").is_file(),
        "go": (root / "go.mod").is_file(),
        "lua": False,
        "notebooks": False,
    }
    present = {stack: count for stack, count in counts.items() if count > 0 or markers[stack]}
    return {
        "present": present,
        "has_typescript": ts_count > 0 or (root / "tsconfig.json").is_file() or "typescript" in node_deps,
        "has_react": react_count > 0 or "react" in node_deps,
        "typescript_files": ts_count,
        "react_files": react_count,
    }


def _parse_workflow_jobs(text: str) -> list[str]:
    jobs: list[str] = []
    in_jobs = False
    job_indent: int | None = None
    for raw_line in text.splitlines():
        stripped = raw_line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        indent = len(raw_line) - len(raw_line.lstrip(" "))
        if indent == 0:
            in_jobs = stripped == "jobs:" or stripped.startswith("jobs:")
            job_indent = None
            continue
        if not in_jobs:
            continue
        if job_indent is None:
            job_indent = indent
        if indent == job_indent and ":" in stripped and not stripped.startswith("-"):
            job_name = stripped.split(":", 1)[0].strip().strip("\"'")
            if job_name:
                jobs.append(job_name)
    return jobs


def _inspect_workflows(root: Path) -> dict[str, Any]:
    wf_dir = root / ".github" / "workflows"
    entries: list[dict[str, Any]] = []
    ci_workflows: list[str] = []
    if wf_dir.is_dir():
        for path in sorted([*wf_dir.glob("*.yml"), *wf_dir.glob("*.yaml")]):
            text = _read_text(path) or ""
            rel = path.relative_to(root).as_posix()
            entries.append(
                {
                    "path": rel,
                    "jobs": _parse_workflow_jobs(text),
                    "legacy_tools": [name for name, pat in WORKFLOW_LEGACY_PATTERNS if pat.search(text)],
                }
            )
            if path.stem.lower() not in NON_CI_WORKFLOW_STEMS:
                ci_workflows.append(rel)

    has_check_yml = (wf_dir / "check.yml").is_file()
    fragmented = len(ci_workflows) > 1 or (len(ci_workflows) == 1 and not has_check_yml)
    return {
        "files": entries,
        "ci_workflow_count": len(ci_workflows),
        "has_check_yml": has_check_yml,
        "fragmented": fragmented,
    }


def _read_ini_sections(root: Path) -> dict[str, set[str]]:
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


def _legacy_python_tools(root: Path, pyproject: dict[str, Any]) -> list[dict[str, Any]]:
    py_deps = _collect_python_deps(root, pyproject)
    py_tools = _as_dict(pyproject.get("tool"))
    ini_sections = _read_ini_sections(root)
    specs: tuple[tuple[str, tuple[str, ...], str, tuple[str, ...]], ...] = (
        ("black", (".black.toml",), "black", ()),
        ("isort", (".isort.cfg",), "isort", ("isort",)),
        ("flake8", (".flake8",), "flake8", ("flake8",)),
        ("pylint", (".pylintrc", "pylintrc"), "pylint", ("pylint",)),
        ("mypy", ("mypy.ini", ".mypy.ini"), "mypy", ("mypy",)),
        ("pyright", ("pyrightconfig.json",), "pyright", ()),
    )
    findings: list[dict[str, Any]] = []
    for tool_name, cfg_files, tool_key, ini_keys in specs:
        ev = [name for name in cfg_files if (root / name).is_file()]
        if tool_key in py_tools:
            ev.append(f"pyproject.toml:[tool.{tool_key}]")
        ev.extend(
            f"{ini_name}:[{ini_key}]"
            for ini_name, sections in ini_sections.items()
            for ini_key in ini_keys
            if ini_key in sections or any(sec.startswith(f"{ini_key}-") for sec in sections)
        )
        if tool_name in py_deps:
            ev.append(f"python-dep:{tool_name}")
        if ev:
            findings.append({"category": "python", "tool": tool_name, "evidence": sorted(set(ev))})
    return findings


def _legacy_web_tools(root: Path, files: list[str], *, package_json: dict[str, Any]) -> list[dict[str, Any]]:
    node_deps = _collect_node_deps(package_json)
    findings: list[dict[str, Any]] = []

    def add(tool: str, evidence: list[str]) -> None:
        if evidence:
            findings.append({"category": "web", "tool": tool, "evidence": sorted(set(evidence))})

    prettier_ev = [
        rel
        for rel in files
        if Path(rel).name.startswith((".prettierrc", "prettier.config.")) or Path(rel).name == ".prettierignore"
    ]
    if "prettier" in package_json:
        prettier_ev.append("package.json:prettier")
    prettier_ev.extend(
        f"package.json-dep:{dep}" for dep in node_deps if dep == "prettier" or dep.startswith("prettier-plugin-")
    )
    add("prettier", prettier_ev)

    eslint_ev = [
        rel
        for rel in files
        if Path(rel).name.startswith((".eslintrc", "eslint.config.")) or Path(rel).name == ".eslintignore"
    ]
    if "eslintConfig" in package_json:
        eslint_ev.append("package.json:eslintConfig")
    eslint_ev.extend(
        f"package.json-dep:{dep}"
        for dep in node_deps
        if dep == "eslint" or dep.startswith(("eslint-", "@eslint/", "@typescript-eslint/"))
    )
    add("eslint", eslint_ev)

    husky_ev = ([".husky/"] if (root / ".husky").is_dir() else []) + (
        ["package.json-dep:husky"] if "husky" in node_deps else []
    )
    add("husky", husky_ev)

    lint_staged_ev = [rel for rel in files if Path(rel).name.startswith((".lintstagedrc", "lint-staged.config."))]
    if "lint-staged" in package_json:
        lint_staged_ev.append("package.json:lint-staged")
    if "lint-staged" in node_deps:
        lint_staged_ev.append("package.json-dep:lint-staged")
    add("lint-staged", lint_staged_ev)

    biome_ev = [rel for rel in files if Path(rel).name in {"biome.json", "biome.jsonc"}]
    if "@biomejs/biome" in node_deps:
        biome_ev.append("package.json-dep:@biomejs/biome")
    add("biome", biome_ev)
    return findings


def _inspect_legacy_tooling(
    root: Path,
    files: list[str],
    *,
    pyproject: dict[str, Any],
    package_json: dict[str, Any],
    workflows: dict[str, Any],
) -> list[dict[str, Any]]:
    findings = _legacy_python_tools(root, pyproject)
    findings.extend(_legacy_web_tools(root, files, package_json=package_json))

    node_deps = _collect_node_deps(package_json)
    mdlint_ev = [rel for rel in files if Path(rel).name.startswith(".markdownlint")]
    mdlint_ev.extend(f"package.json-dep:{dep}" for dep in node_deps if "markdownlint" in dep)
    if mdlint_ev:
        findings.append({"category": "markdown", "tool": "markdownlint", "evidence": sorted(set(mdlint_ev))})

    if (root / ".luacheckrc").is_file():
        findings.append({"category": "lua", "tool": "luacheck", "evidence": [".luacheckrc"]})

    precommit_ev: list[str] = []
    if "pre-commit" in _collect_python_deps(root, pyproject):
        precommit_ev.append("python-dep:pre-commit")
    precommit_ev.extend(f"{wf['path']}:pre-commit" for wf in workflows["files"] if "pre-commit" in wf["legacy_tools"])
    git_hook = root / ".git" / "hooks" / "pre-commit"
    if git_hook.is_file() and "prek" not in (_read_text(git_hook) or "").lower():
        precommit_ev.append(".git/hooks/pre-commit (non-prek shim)")
    if precommit_ev:
        if (root / ".pre-commit-config.yaml").is_file():
            precommit_ev.append("note: keep .pre-commit-config.yaml for prek")
        findings.append({"category": "pre-commit", "tool": "pre-commit", "evidence": sorted(set(precommit_ev))})

    bots = (
        ".github/dependabot.yml",
        ".github/dependabot.yaml",
        "renovate.json",
        "renovate.json5",
        ".renovaterc",
        ".renovaterc.json",
        ".github/renovate.json",
    )
    bot_ev = [rel for rel in bots if (root / rel).is_file()]
    if bot_ev:
        findings.append({"category": "dependency-bots", "tool": "dependabot/renovate", "evidence": bot_ev})
    return findings


def _missing_python_configs(root: Path, pyproject: dict[str, Any], *, precommit_text: str) -> list[dict[str, str]]:
    missing: list[dict[str, str]] = []

    def need(item: str, detail: str) -> None:
        missing.append({"scope": "python", "item": item, "detail": detail})

    if not (root / "pyproject.toml").is_file():
        need("pyproject.toml", "uv project metadata and tool settings")
    if not (root / "uv.lock").is_file():
        need("uv.lock", "committed uv lockfile")

    ruff_cfg = _as_dict(_as_dict(pyproject.get("tool")).get("ruff"))
    if not ruff_cfg:
        need("[tool.ruff]", "Ruff config in pyproject.toml")
    else:
        lint_cfg = _as_dict(ruff_cfg.get("lint"))
        if lint_cfg.get("select") != ["ALL"]:
            need("[tool.ruff.lint] select = ['ALL']", "enable Ruff ALL ruleset")
        if _as_dict(lint_cfg.get("pylint")).get("max-positional-args") != EXPECTED_MAX_POSITIONAL_ARGS:
            need("[tool.ruff.lint.pylint] max-positional-args = 2", "cap positional args via PLR0917")
        tidy_cfg = _as_dict(lint_cfg.get("flake8-tidy-imports"))
        if not _as_dict(tidy_cfg.get("banned-api")):
            need("[tool.ruff.lint.flake8-tidy-imports.banned-api]", "ban cast, unittest and dynamic imports")

    if "ty" not in _collect_python_deps(root, pyproject) and "ty-pre-commit" not in precommit_text:
        need("ty", "add ty to dev deps and .pre-commit-config.yaml")
    return missing


def _missing_web_configs(root: Path, stacks: dict[str, Any], *, package_json: dict[str, Any]) -> list[dict[str, str]]:
    missing: list[dict[str, str]] = []
    node_deps = _collect_node_deps(package_json)

    def need(item: str, detail: str) -> None:
        missing.append({"scope": "web", "item": item, "detail": detail})

    for rel, detail in (
        ("package-lock.json", "committed npm lockfile"),
        (".oxfmtrc.json", "oxfmt config"),
        (".oxlintrc.json", "oxlint config"),
    ):
        if not (root / rel).is_file():
            need(rel, detail)
    for dep, detail in (
        ("oxfmt", "install oxfmt in package.json"),
        ("oxlint", "install oxlint in package.json"),
    ):
        if dep not in node_deps:
            need(f"{dep} devDependency", detail)
    if stacks["has_typescript"] and "oxlint-tsgolint" not in node_deps:
        need("oxlint-tsgolint devDependency", "type-aware oxlint checks replacing tsc")
    return missing


def _missing_systems_configs(root: Path, present: dict[str, int]) -> list[dict[str, str]]:
    missing: list[dict[str, str]] = []
    if "rust" in present:
        cargo = _read_toml(root / "Cargo.toml")
        has_clippy = "clippy" in _as_dict(cargo.get("lints")) or "clippy" in _as_dict(
            _as_dict(cargo.get("workspace")).get("lints"),
        )
        if not has_clippy:
            missing.append({"scope": "rust", "item": "[lints.clippy]", "detail": "clippy lints in Cargo.toml"})
    if "go" in present and not ((root / ".golangci.yml").is_file() or (root / ".golangci.yaml").is_file()):
        missing.append({"scope": "go", "item": ".golangci.yml", "detail": "golangci-lint v2 config"})
    if "lua" in present:
        if not ((root / "stylua.toml").is_file() or (root / ".stylua.toml").is_file()):
            missing.append({"scope": "lua", "item": "stylua.toml", "detail": "StyLua formatting config"})
        if not (root / ".emmyrc.json").is_file():
            missing.append({"scope": "lua", "item": ".emmyrc.json", "detail": "emmylua_check config"})
    return missing


def _inspect_missing_configs(
    root: Path,
    stacks: dict[str, Any],
    *,
    pyproject: dict[str, Any],
    package_json: dict[str, Any],
) -> list[dict[str, str]]:
    missing: list[dict[str, str]] = [
        {"scope": "universal", "item": rel, "detail": detail}
        for rel, detail in (
            (".pre-commit-config.yaml", "prek hook list"),
            (".github/workflows/check.yml", "single CI workflow"),
            (".editorconfig", "editor indent and line-length settings"),
            (".rumdl.toml", "Markdown formatting and lint config"),
            ("AGENTS.md", "agent development instructions"),
            ("README.md", "project overview"),
        )
        if not (root / rel).is_file()
    ]

    precommit_text = _read_text(root / ".pre-commit-config.yaml") or ""
    if precommit_text and "max-file-lines" not in precommit_text:
        missing.append(
            {
                "scope": "universal",
                "item": "max-file-lines hook",
                "detail": "1,000-line hard cap in .pre-commit-config.yaml",
            }
        )

    present = stacks["present"]
    if "python" in present:
        missing.extend(_missing_python_configs(root, pyproject, precommit_text=precommit_text))
    if "web" in present:
        missing.extend(_missing_web_configs(root, stacks, package_json=package_json))
    missing.extend(_missing_systems_configs(root, present))
    return missing


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


def _parse_simple_yaml_list(text: str, key: str) -> list[str]:
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


def _parse_simple_yaml_bool(text: str, key: str) -> bool | None:
    pattern = re.compile(rf"^{re.escape(key)}\s*:")
    for raw_line in text.splitlines():
        if pattern.match(raw_line):
            val = raw_line.split(":", 1)[1].split("#", 1)[0].strip().lower()
            if val == "true":
                return True
            if val == "false":
                return False
    return None


def _inspect_byor(root: Path, stacks: dict[str, Any]) -> dict[str, Any]:
    config_path = root / ".byor" / "config.yml"
    local_path = root / ".byor" / "local.yml"
    project_rules_dir = root / ".byor" / "rules" / "project"

    config_text = _read_text(config_path) or ""
    local_text = _read_text(local_path) or ""
    packages = _parse_simple_yaml_list(local_text, "packages") or _parse_simple_yaml_list(config_text, "packages")

    present = stacks["present"]
    expected = ["craft"]
    if "python" in present:
        expected.append("python")
    if "web" in present:
        expected.append("web")

    project_rules: list[str] = []
    if project_rules_dir.is_dir():
        project_rules = sorted(
            path.relative_to(root).as_posix()
            for path in [*project_rules_dir.rglob("*.yml"), *project_rules_dir.rglob("*.yaml")]
            if path.is_file()
        )

    precommit_text = _read_text(root / ".pre-commit-config.yaml") or ""
    enabled_set = set(packages)
    return {
        "initialized": config_path.is_file() or local_path.is_file(),
        "has_config_yml": config_path.is_file(),
        "has_local_yml": local_path.is_file(),
        "packages": packages,
        "expected_packages": expected,
        "missing_packages": [pkg for pkg in expected if pkg not in enabled_set],
        "stale_packages": [pkg for pkg in packages if pkg == "style"],
        "gate_enabled": _parse_simple_yaml_bool(config_text, "gate") is True,
        "project_rules": project_rules,
        "project_rules_count": len(project_rules),
        "needs_ast_grep_hook": len(project_rules) > 0 and "ast-grep" not in precommit_text,
    }


def _inspect_file_sizes(root: Path, files: list[str]) -> dict[str, Any]:
    warning: list[dict[str, Any]] = []
    hard_cap: list[dict[str, Any]] = []
    for rel in files:
        if Path(rel).suffix.lower() in SKIP_SIZE_EXTS or SKIP_SIZE_RE.search(rel):
            continue
        try:
            raw = (root / rel).read_bytes()
        except OSError:
            continue
        if b"\x00" in raw[:8192]:
            continue
        line_count = raw.count(b"\n") + (1 if raw and not raw.endswith(b"\n") else 0)
        if line_count > HARD_CAP_LINE_THRESHOLD:
            hard_cap.append({"path": rel, "lines": line_count})
        elif line_count > WARNING_LINE_THRESHOLD:
            warning.append({"path": rel, "lines": line_count})

    warning.sort(key=lambda item: (-item["lines"], item["path"]))
    hard_cap.sort(key=lambda item: (-item["lines"], item["path"]))
    return {
        "warning_threshold": WARNING_LINE_THRESHOLD,
        "hard_cap_threshold": HARD_CAP_LINE_THRESHOLD,
        "warning_count": len(warning),
        "hard_cap_count": len(hard_cap),
        "warning_files": warning,
        "hard_cap_files": hard_cap,
    }


def _inspect_git_hygiene(root: Path) -> dict[str, bool]:
    return {
        "has_git_blame_ignore_revs": (root / ".git-blame-ignore-revs").is_file(),
        "has_backlog_md": (root / "BACKLOG.md").is_file(),
        "has_agents_md": (root / "AGENTS.md").is_file(),
        "has_readme_md": (root / "README.md").is_file(),
    }


def audit_repository(root: Path) -> dict[str, Any]:
    """Run all read-only audit checks against root and return a structured report."""
    resolved = root.resolve()
    files, is_git_repo = _list_repo_files(resolved)
    pyproject = _read_toml(resolved / "pyproject.toml")
    package_json = _read_json(resolved / "package.json")
    stacks = _detect_stacks(resolved, files, package_json=package_json)
    workflows = _inspect_workflows(resolved)
    return {
        "path": str(resolved),
        "is_git_repo": is_git_repo,
        "total_files": len(files),
        "stacks": stacks,
        "legacy_tooling": _inspect_legacy_tooling(
            resolved,
            files,
            pyproject=pyproject,
            package_json=package_json,
            workflows=workflows,
        ),
        "workflows": workflows,
        "missing_configs": _inspect_missing_configs(
            resolved,
            stacks,
            pyproject=pyproject,
            package_json=package_json,
        ),
        "byor": _inspect_byor(resolved, stacks),
        "file_sizes": _inspect_file_sizes(resolved, files),
        "git_hygiene": _inspect_git_hygiene(resolved),
    }


def _format_stacks_section(stacks: dict[str, Any]) -> list[str]:
    lines = ["## Stacks", ""]
    present: dict[str, int] = stacks["present"]
    if not present:
        return [*lines, "No recognized language stacks found."]
    lines.extend(["| Stack | Files |", "| --- | ---: |"])
    for name, count in present.items():
        extras = [
            tag
            for tag, flag in (("TypeScript", stacks["has_typescript"]), ("React", stacks["has_react"]))
            if name == "web" and flag
        ]
        label = f"{name} ({', '.join(extras)})" if extras else name
        lines.append(f"| {label} | {count} |")
    return lines


def _format_workflows_section(workflows: dict[str, Any]) -> list[str]:
    lines = ["## Workflows", ""]
    wf_files: list[dict[str, Any]] = workflows["files"]
    if not wf_files:
        return [*lines, "No files under `.github/workflows/`."]
    lines.extend(["| Workflow | Jobs | Legacy tools |", "| --- | --- | --- |"])
    lines.extend(
        f"| `{wf['path']}` | {', '.join(wf['jobs']) or '-'} | {', '.join(wf['legacy_tools']) or '-'} |"
        for wf in wf_files
    )
    if workflows["fragmented"]:
        lines.extend(["", "Workflow fragmentation flagged: consolidate CI into `.github/workflows/check.yml`."])
    return lines


def _format_sizes_section(sizes: dict[str, Any]) -> list[str]:
    lines = [
        "## Source file sizes",
        "",
        f"- Over {sizes['hard_cap_threshold']} lines (hard cap): {sizes['hard_cap_count']}",
        f"- {sizes['warning_threshold'] + 1}-{sizes['hard_cap_threshold']} lines (warning): {sizes['warning_count']}",
    ]
    if sizes["hard_cap_files"] or sizes["warning_files"]:
        lines.extend(["", "| Tier | Lines | File |", "| --- | ---: | --- |"])
        lines.extend(f"| hard cap (>1000) | {e['lines']} | `{e['path']}` |" for e in sizes["hard_cap_files"])
        lines.extend(f"| warning (>600) | {e['lines']} | `{e['path']}` |" for e in sizes["warning_files"])
    return lines


def format_markdown(report: dict[str, Any]) -> str:
    """Format an audit report as concise Markdown tables."""
    lines: list[str] = [f"# Repository audit: `{report['path']}`", "", *_format_stacks_section(report["stacks"])]

    lines.extend(["", "## Legacy tooling", ""])
    legacy: list[dict[str, Any]] = report["legacy_tooling"]
    if legacy:
        lines.extend(["| Category | Tool | Evidence |", "| --- | --- | --- |"])
        lines.extend(
            f"| {e['category']} | {e['tool']} | {', '.join(f'`{ev}`' for ev in e['evidence'])} |" for e in legacy
        )
    else:
        lines.append("None detected.")

    lines.extend(["", *_format_workflows_section(report["workflows"])])

    lines.extend(["", "## Missing canonical files and configs", ""])
    missing: list[dict[str, str]] = report["missing_configs"]
    if missing:
        lines.extend(["| Scope | Missing | Why |", "| --- | --- | --- |"])
        lines.extend(f"| {m['scope']} | `{m['item']}` | {m['detail']} |" for m in missing)
    else:
        lines.append("All canonical files and configs are present.")

    byor = report["byor"]
    lines.extend(
        [
            "",
            "## BYOR wiring",
            "",
            "| Check | Status |",
            "| --- | --- |",
            f"| Initialized (`.byor/`) | {'yes' if byor['initialized'] else 'no'} |",
            f"| Enabled packages | {', '.join(byor['packages']) or 'none'} |",
            f"| Expected packages | {', '.join(byor['expected_packages'])} |",
            f"| Missing packages | {', '.join(byor['missing_packages']) or 'none'} |",
            f"| Stale packages | {', '.join(byor['stale_packages']) or 'none'} |",
            f"| `gate: true` set (should be false) | {'yes' if byor['gate_enabled'] else 'no'} |",
            f"| Project rules (`.byor/rules/project/`) | {byor['project_rules_count']} |",
            f"| Needs `ast-grep` prek hook | {'yes' if byor['needs_ast_grep_hook'] else 'no'} |",
            "",
            *_format_sizes_section(report["file_sizes"]),
        ]
    )

    hygiene = report["git_hygiene"]
    lines.extend(
        [
            "",
            "## Git hygiene",
            "",
            "| File | Present |",
            "| --- | --- |",
            f"| `.git-blame-ignore-revs` | {'yes' if hygiene['has_git_blame_ignore_revs'] else 'no'} |",
            f"| `BACKLOG.md` | {'yes' if hygiene['has_backlog_md'] else 'no'} |",
            f"| `AGENTS.md` | {'yes' if hygiene['has_agents_md'] else 'no'} |",
            f"| `README.md` | {'yes' if hygiene['has_readme_md'] else 'no'} |",
        ]
    )
    return "\n".join(lines) + "\n"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Audit a repository against the project-setup standards.")
    parser.add_argument("path", nargs="?", default=".", help="Path to the target repository (defaults to .).")
    parser.add_argument("--json", action="store_true", dest="as_json", help="Emit structured JSON instead of Markdown.")
    args = parser.parse_args(argv)

    target = Path(args.path)
    if not target.is_dir():
        sys.stderr.write(f"error: {target} is not a directory\n")
        return 2

    report = audit_repository(target)
    output = f"{json.dumps(report, indent=2)}\n" if args.as_json else format_markdown(report)
    sys.stdout.write(output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
