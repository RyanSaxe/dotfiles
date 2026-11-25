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
EXPECTED_MAX_COMPLEXITY = 8
EXPECTED_MAX_BRANCHES = 10
EXPECTED_MAX_NESTED_BLOCKS = 4
MAX_RULE_PREVIEW = 4
PARITY_TOOLS = ("shellcheck", "shfmt", "deadnix", "statix", "luacheck")

OXLINT_COMMON_RULES = (
    frozenset({"complexity", "max-depth", "max-nested-callbacks", "max-params", "curly", "import/no-cycle", "eqeqeq"})
    | frozenset({"no-var", "prefer-const", "no-param-reassign", "no-nested-ternary", "no-else-return", "no-lonely-if"})
    | frozenset({"unicorn/no-negated-condition"})
)
OXLINT_TS_RULES = (
    frozenset(
        {"typescript/consistent-type-assertions", "typescript/no-explicit-any", "typescript/no-non-null-assertion"}
    )
    | frozenset({"typescript/switch-exhaustiveness-check", "typescript/no-misused-promises"})
    | frozenset({"typescript/explicit-function-return-type"})
)
OXLINT_REACT_PLUGINS = frozenset({"react", "jsx-a11y"})
GOLANGCI_REQUIRED = frozenset({"cyclop", "gocognit", "nestif", "revive", "gosec"}) | frozenset(
    {"errcheck", "errorlint", "staticcheck", "gofumpt"}
)
EMMY_REQUIRED_ERRORS = (
    frozenset(
        {"need-check-nil", "param-type-mismatch", "return-type-mismatch", "unnecessary-if", "assign-type-mismatch"}
    )
    | frozenset({"inject-field", "redundant-return-value", "redundant-parameter", "unused", "redefined-local"})
    | frozenset({"unreachable-code"})
)
JSONC_TOKEN_RE = re.compile(r'"(?:\\.|[^"\\])*"|//[^\n]*|/\*.*?\*/', re.DOTALL)
ZSH_SHEBANG_RE = re.compile(rb"^#!\s*(?:/\S*/)?(?:env\s+(?:-\S+\s+)*)?zsh(?:\s|$)")
SETUP_UV_RE = re.compile(r"astral-sh/setup-uv(?:@([^\s'\"#]+))?")
SEMVER_PIN_RE = re.compile(r"v?\d+\.\d+\.\d+")

PRUNE_DIRS = frozenset({".git", "node_modules", ".venv", "venv", "target", "dist", "build", "vendor"}) | frozenset(
    {"__pycache__", ".mypy_cache", ".pytest_cache", ".ruff_cache", ".rumdl_cache", ".next", ".astro"}
)
SKIP_SIZE_EXTS = (
    frozenset({".lock", ".svg", ".json", ".jsonc", ".csv", ".tsv", ".jsonl", ".ndjson", ".sql", ".xml", ".txt"})
    | frozenset({".md", ".mdx", ".markdown", ".map", ".snap", ".po", ".pot"})
    | frozenset({".png", ".jpg", ".jpeg", ".gif", ".webp", ".ico", ".pdf", ".mp4", ".webm", ".mov"})
    | frozenset({".woff", ".woff2", ".ttf", ".otf", ".eot"})
    | frozenset({".zip", ".tar", ".gz", ".wasm", ".pyc", ".so", ".dylib", ".dll", ".exe"})
)

SKIP_SIZE_RE = re.compile(
    r"(^|/)([^/]+-lock\.[^/]+|[^/]+\.(min|generated|gen)\.[^/]+|[^/]+_pb2\.py|[^/]+\.pb\.go)$",
)

STACK_EXTS: dict[str, frozenset[str]] = {
    "python": frozenset({".py", ".pyi"}),
    "web": (
        frozenset({".ts", ".tsx", ".mts", ".cts", ".js", ".jsx", ".mjs", ".cjs"})
        | frozenset({".astro", ".svelte", ".vue", ".css", ".html"})
    ),
    "markdown": frozenset({".md", ".mdx", ".markdown"}),
    "rust": frozenset({".rs"}),
    "go": frozenset({".go"}),
    "lua": frozenset({".lua"}),
    "notebooks": frozenset({".ipynb"}),
    "shell": frozenset({".sh", ".bash", ".zsh"}),
    "nix": frozenset({".nix"}),
}

TS_EXTS = frozenset({".ts", ".tsx", ".mts", ".cts"})
REACT_EXTS = frozenset({".jsx", ".tsx"})

_LEGACY_WF_TOOLS = frozenset({"prettier", "eslint", "markdownlint", "black", "isort", "flake8"}) | frozenset(
    {"pylint", "mypy", "pyright", "biome", "selene", "husky"}
)
WORKFLOW_LEGACY_PATTERNS: tuple[tuple[str, re.Pattern[str]], ...] = (
    ("pre-commit", re.compile(r"pre-commit/action|\bpre-commit\s+run\b")),
    *((tool, re.compile(rf"\b{tool}\b")) for tool in sorted(_LEGACY_WF_TOOLS)),
)

NON_CI_WORKFLOW_STEMS = frozenset({"release", "publish", "deploy", "pages", "docs", "codeql", "stale", "labeler"})


def _read_text(path: Path) -> str | None:
    try:
        return path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return None


def _read_json(path: Path, *, jsonc: bool = False) -> dict[str, Any]:
    text = _read_text(path)
    if text is None:
        return {}
    if jsonc:
        text = JSONC_TOKEN_RE.sub(lambda m: m.group(0) if m.group(0).startswith('"') else "", text)
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
        return subprocess.run([git_bin, "-C", str(root), *args], capture_output=True, check=False)
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


def _has_zsh_files(root: Path, files: list[str]) -> bool:
    for rel in files:
        path = Path(rel)
        suffix = path.suffix.lower()
        if suffix == ".zsh" or path.name in {"zshrc", "zshrc.minimal", ".zshrc"}:
            return True
        if suffix not in {".sh", ".bash", ""}:
            continue
        try:
            with (root / rel).open("rb") as handle:
                first_line = handle.readline(256)
        except OSError:
            continue
        if ZSH_SHEBANG_RE.match(first_line):
            return True
    return False


def _is_fixture_path(rel: str) -> bool:
    return "fixtures" in Path(rel).parts[:-1]


def _detect_stacks(root: Path, files: list[str], *, package_json: dict[str, Any]) -> dict[str, Any]:
    source_files = [rel for rel in files if not _is_fixture_path(rel)]
    counts: dict[str, int] = dict.fromkeys(STACK_EXTS, 0)
    ts_count = 0
    react_count = 0
    for rel in source_files:
        ext = Path(rel).suffix.lower()
        for stack, exts in STACK_EXTS.items():
            if ext in exts:
                counts[stack] += 1
        ts_count += int(ext in TS_EXTS)
        react_count += int(ext in REACT_EXTS)

    node_deps = _collect_node_deps(package_json)
    has_python_marker = (
        (root / "pyproject.toml").is_file()
        or (root / "setup.py").is_file()
        or any(root.glob("requirements*.txt"))
        or any(Path(rel).name == "pyproject.toml" for rel in source_files)
    )
    markers = {
        "python": has_python_marker,
        "web": (root / "package.json").is_file(),
        "markdown": False,
        "rust": (root / "Cargo.toml").is_file(),
        "go": (root / "go.mod").is_file() or any(Path(rel).name == "go.mod" for rel in source_files),
        "lua": False,
        "notebooks": False,
        "shell": False,
        "nix": (root / "flake.nix").is_file(),
    }
    present = {stack: count for stack, count in counts.items() if count > 0 or markers[stack]}
    return {
        "present": present,
        "has_typescript": ts_count > 0 or (root / "tsconfig.json").is_file() or "typescript" in node_deps,
        "has_react": react_count > 0 or "react" in node_deps,
        "has_zsh": _has_zsh_files(root, source_files),
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


def _read_workflow_entry(root: Path, path: Path) -> tuple[dict[str, Any], bool]:
    text = _read_text(path) or ""
    entry = {
        "path": path.relative_to(root).as_posix(),
        "jobs": _parse_workflow_jobs(text),
        "legacy_tools": [name for name, pat in WORKFLOW_LEGACY_PATTERNS if pat.search(text)],
    }
    return entry, bool(re.search(r"\bprek\b", text))


def _inspect_workflows(root: Path) -> dict[str, Any]:
    wf_dir = root / ".github" / "workflows"
    entries: list[dict[str, Any]] = []
    ci_workflows: list[str] = []
    prek_stems: set[str] = set()
    if wf_dir.is_dir():
        for path in sorted([*wf_dir.glob("*.yml"), *wf_dir.glob("*.yaml")]):
            entry, runs_prek = _read_workflow_entry(root, path)
            entries.append(entry)
            stem = path.stem.lower()
            if runs_prek:
                prek_stems.add(stem)
            if stem not in NON_CI_WORKFLOW_STEMS:
                ci_workflows.append(entry["path"])

    has_check_yml = (wf_dir / "check.yml").is_file() or (wf_dir / "check.yaml").is_file()
    if has_check_yml and "ci" in prek_stems and "check" not in prek_stems:
        ci_workflows = [rel for rel in ci_workflows if Path(rel).stem.lower() != "check"]
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
    named = [(rel, Path(rel).name) for rel in files]
    groups = (
        (
            "prettier",
            [rel for rel, n in named if n.startswith((".prettierrc", "prettier.config.")) or n == ".prettierignore"]
            + (["package.json:prettier"] if "prettier" in package_json else [])
            + [f"package.json-dep:{d}" for d in node_deps if d == "prettier" or d.startswith("prettier-plugin-")],
        ),
        (
            "eslint",
            [rel for rel, n in named if n.startswith((".eslintrc", "eslint.config.")) or n == ".eslintignore"]
            + (["package.json:eslintConfig"] if "eslintConfig" in package_json else [])
            + [
                f"package.json-dep:{d}"
                for d in node_deps
                if d == "eslint" or d.startswith(("eslint-", "@eslint/", "@typescript-eslint/"))
            ],
        ),
        (
            "husky",
            ([".husky/"] if (root / ".husky").is_dir() else [])
            + (["package.json-dep:husky"] if "husky" in node_deps else []),
        ),
        (
            "lint-staged",
            [rel for rel, n in named if n.startswith((".lintstagedrc", "lint-staged.config."))]
            + (["package.json:lint-staged"] if "lint-staged" in package_json else [])
            + (["package.json-dep:lint-staged"] if "lint-staged" in node_deps else []),
        ),
        (
            "biome",
            [rel for rel, n in named if n in {"biome.json", "biome.jsonc"}]
            + (["package.json-dep:@biomejs/biome"] if "@biomejs/biome" in node_deps else []),
        ),
    )
    return [{"category": "web", "tool": tool, "evidence": sorted(set(ev))} for tool, ev in groups if ev]


def _legacy_lua_tools(root: Path, files: list[str], *, workflows: dict[str, Any]) -> list[dict[str, Any]]:
    findings: list[dict[str, Any]] = []
    if (root / ".luacheckrc").is_file():
        findings.append({"category": "lua", "tool": "luacheck", "evidence": [".luacheckrc"]})
    selene_ev = [rel for rel in files if Path(rel).name == "selene.toml"]
    selene_ev.extend(f"{wf['path']}:selene" for wf in workflows["files"] if "selene" in wf["legacy_tools"])
    if selene_ev:
        findings.append({"category": "lua", "tool": "selene", "evidence": sorted(set(selene_ev))})
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
    findings.extend(_legacy_lua_tools(root, files, workflows=workflows))

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

    bots = frozenset(
        {".github/dependabot.yml", ".github/dependabot.yaml", "renovate.json", "renovate.json5"}
    ) | frozenset({".renovaterc", ".renovaterc.json", ".github/renovate.json"})
    bot_ev = sorted(rel for rel in bots if (root / rel).is_file())
    if bot_ev:
        findings.append({"category": "dependency-bots", "tool": "dependabot/renovate", "evidence": bot_ev})
    return findings


def _within_cap(value: object, limit: int) -> bool:
    return isinstance(value, int) and not isinstance(value, bool) and 1 <= value <= limit


def _missing_ruff_rules(ruff_cfg: dict[str, Any]) -> list[dict[str, str]]:
    if not ruff_cfg:
        return [{"scope": "python", "item": "[tool.ruff]", "detail": "Ruff config in pyproject.toml"}]
    lint_cfg = _as_dict(ruff_cfg.get("lint"))
    pylint_cfg = _as_dict(lint_cfg.get("pylint"))
    mccabe_cfg = _as_dict(lint_cfg.get("mccabe"))
    caps = (
        (mccabe_cfg, "mccabe", "max-complexity", EXPECTED_MAX_COMPLEXITY, "cap cyclomatic complexity via C901"),
        (pylint_cfg, "pylint", "max-positional-args", EXPECTED_MAX_POSITIONAL_ARGS, "cap positional args via PLR0917"),
        (pylint_cfg, "pylint", "max-branches", EXPECTED_MAX_BRANCHES, "cap branches via PLR0912"),
        (pylint_cfg, "pylint", "max-nested-blocks", EXPECTED_MAX_NESTED_BLOCKS, "cap nesting depth via PLR1702"),
    )
    checks = [
        (lint_cfg.get("select") != ["ALL"], "[tool.ruff.lint] select = ['ALL']", "enable Ruff ALL ruleset"),
        *(
            (not _within_cap(cfg.get(key), limit), f"[tool.ruff.lint.{sec}] {key} <= {limit}", detail)
            for cfg, sec, key, limit, detail in caps
        ),
        (
            not _as_dict(_as_dict(lint_cfg.get("flake8-tidy-imports")).get("banned-api")),
            "[tool.ruff.lint.flake8-tidy-imports.banned-api]",
            "ban cast, unittest and dynamic imports",
        ),
    ]
    return [{"scope": "python", "item": item, "detail": detail} for is_missing, item, detail in checks if is_missing]


def _missing_setup_uv_pin(root: Path) -> list[dict[str, str]]:
    wf_dir = root / ".github" / "workflows"
    if not wf_dir.is_dir():
        return []
    missing: list[dict[str, str]] = []
    for path in sorted([*wf_dir.glob("*.yml"), *wf_dir.glob("*.yaml")]):
        text = _read_text(path) or ""
        unpinned = sorted(
            {
                f"@{ref}" if ref else "(unpinned)"
                for m in SETUP_UV_RE.finditer(text)
                if not ((ref := m.group(1)) and SEMVER_PIN_RE.fullmatch(ref))
            }
        )
        if unpinned:
            detail = f"pin astral-sh/setup-uv to full semver like @v10.4.0 (found: {', '.join(unpinned)})"
            missing.append({"scope": "universal", "item": f"{path.name} setup-uv semver pin", "detail": detail})
    return missing


def _missing_python_project_configs(proj_dir: Path, root: Path, *, precommit_text: str) -> list[dict[str, str]]:
    prefix = "" if proj_dir == root else f"{proj_dir.relative_to(root).as_posix()}/"
    pyproject = _read_toml(proj_dir / "pyproject.toml")
    missing: list[dict[str, str]] = []
    if not (proj_dir / "uv.lock").is_file():
        missing.append({"scope": "python", "item": f"{prefix}uv.lock", "detail": "committed uv lockfile"})
    missing.extend(
        {**entry, "item": f"{prefix}{entry['item']}"}
        for entry in _missing_ruff_rules(_as_dict(_as_dict(pyproject.get("tool")).get("ruff")))
    )
    has_ty_hook = "ty-pre-commit" in precommit_text or "ty check" in precommit_text
    if "ty" not in _collect_python_deps(proj_dir, pyproject) and not has_ty_hook:
        detail = "add ty to dev deps and .pre-commit-config.yaml"
        missing.append({"scope": "python", "item": f"{prefix}ty", "detail": detail})
    return missing


def _missing_python_configs(root: Path, files: list[str], *, precommit_text: str) -> list[dict[str, str]]:
    proj_dirs = (
        [root]
        if (root / "pyproject.toml").is_file()
        else sorted(
            {root / Path(r).parent for r in files if not _is_fixture_path(r) and Path(r).name == "pyproject.toml"}
        )
    )
    if not proj_dirs:
        first = {"scope": "python", "item": "pyproject.toml", "detail": "uv project metadata and tool settings"}
        return [first, *_missing_python_project_configs(root, root, precommit_text=precommit_text)]
    return [e for d in proj_dirs for e in _missing_python_project_configs(d, root, precommit_text=precommit_text)]


def _missing_react_oxlint_plugins(cfg: dict[str, Any]) -> list[dict[str, str]]:
    raw = cfg.get("plugins")
    plugins = {p for p in raw if isinstance(p, str)} if isinstance(raw, list) else set()
    absent = sorted(OXLINT_REACT_PLUGINS - plugins)
    if not absent:
        return []
    return [{"scope": "web", "item": ".oxlintrc.json React plugins", "detail": f"missing: {', '.join(absent)}"}]


def _missing_oxlint_rules(root: Path, stacks: dict[str, Any]) -> list[dict[str, str]]:
    cfg = _read_json(root / ".oxlintrc.json", jsonc=True)
    rules = _as_dict(cfg.get("rules"))
    required = OXLINT_COMMON_RULES | (OXLINT_TS_RULES if stacks["has_typescript"] else frozenset())
    if stacks["has_react"]:
        required |= frozenset({"no-restricted-imports"})
    absent = sorted(required - rules.keys())
    missing: list[dict[str, str]] = []
    if absent:
        extra = f" (+{len(absent) - MAX_RULE_PREVIEW} more)" if len(absent) > MAX_RULE_PREVIEW else ""
        preview = ", ".join(absent[:MAX_RULE_PREVIEW]) + extra
        missing.append({"scope": "web", "item": ".oxlintrc.json parity rules", "detail": f"missing: {preview}"})
    if stacks["has_react"]:
        missing.extend(_missing_react_oxlint_plugins(cfg))
    return missing


def _missing_web_configs(root: Path, stacks: dict[str, Any], *, package_json: dict[str, Any]) -> list[dict[str, str]]:
    missing: list[dict[str, str]] = []
    node_deps = _collect_node_deps(package_json)
    pkg_mgr = package_json.get("packageManager")
    uses_pnpm = (root / "pnpm-workspace.yaml").is_file() or (isinstance(pkg_mgr, str) and pkg_mgr.startswith("pnpm"))
    lockfile = (
        ("pnpm-lock.yaml", "committed pnpm lockfile") if uses_pnpm else ("package-lock.json", "committed npm lockfile")
    )
    for rel, detail in (lockfile, (".oxfmtrc.json", "oxfmt config"), (".oxlintrc.json", "oxlint config")):
        if not (root / rel).is_file():
            missing.append({"scope": "web", "item": rel, "detail": detail})
    missing.extend(
        {"scope": "web", "item": f"{dep} devDependency", "detail": f"install {dep} in package.json"}
        for dep in ("oxfmt", "oxlint")
        if dep not in node_deps
    )
    if stacks["has_typescript"] and "oxlint-tsgolint" not in node_deps:
        detail = "type-aware oxlint checks replacing tsc"
        missing.append({"scope": "web", "item": "oxlint-tsgolint devDependency", "detail": detail})
    if (root / ".oxlintrc.json").is_file():
        missing.extend(_missing_oxlint_rules(root, stacks))
    return missing


def _missing_rust_configs(root: Path) -> list[dict[str, str]]:
    missing: list[dict[str, str]] = []
    cargo = _read_toml(root / "Cargo.toml")
    clippy_cfg = _as_dict(_as_dict(cargo.get("lints")).get("clippy")) or _as_dict(
        _as_dict(_as_dict(cargo.get("workspace")).get("lints")).get("clippy")
    )
    if not clippy_cfg:
        missing.append({"scope": "rust", "item": "[lints.clippy]", "detail": "clippy lints in Cargo.toml"})
    elif "cognitive_complexity" not in clippy_cfg:
        missing.append(
            {"scope": "rust", "item": "clippy cognitive_complexity", "detail": "add cognitive_complexity = 'warn'"}
        )
    if not ((root / "clippy.toml").is_file() or (root / ".clippy.toml").is_file()):
        missing.append({"scope": "rust", "item": "clippy.toml", "detail": "set cognitive-complexity-threshold = 15"})
    return missing


def _find_golangci_cfg(root: Path, mod_dir: Path) -> Path | None:
    return next(
        (c for d in (mod_dir, Path()) for n in (".golangci.yml", ".golangci.yaml") if (c := root / d / n).is_file()),
        None,
    )


def _missing_go_configs(root: Path, files: list[str]) -> list[dict[str, str]]:
    mod_dirs = sorted(
        {Path(rel).parent for rel in files if not _is_fixture_path(rel) and Path(rel).name == "go.mod"}
    ) or [Path()]
    missing: list[dict[str, str]] = []
    for mod_dir in mod_dirs:
        cfg_path = _find_golangci_cfg(root, mod_dir)
        if cfg_path is None:
            item = ".golangci.yml" if mod_dir == Path() else f"{mod_dir.as_posix()}/.golangci.yml"
            missing.append({"scope": "go", "item": item, "detail": "golangci-lint v2 config"})
            continue
        text = _read_text(cfg_path) or ""
        absent = sorted(name for name in GOLANGCI_REQUIRED if not re.search(rf"\b{re.escape(name)}\b", text))
        if absent:
            rel_cfg = cfg_path.relative_to(root).as_posix()
            detail = f"missing: {', '.join(absent)}"
            missing.append({"scope": "go", "item": f"{rel_cfg} parity linters", "detail": detail})
    return missing


def _missing_lua_configs(root: Path, *, precommit_text: str) -> list[dict[str, str]]:
    missing: list[dict[str, str]] = []
    if not ((root / "stylua.toml").is_file() or (root / ".stylua.toml").is_file()):
        missing.append({"scope": "lua", "item": "stylua.toml", "detail": "StyLua formatting config"})
    emmy_path = root / ".emmyrc.json"
    if not emmy_path.is_file():
        missing.append({"scope": "lua", "item": ".emmyrc.json", "detail": "emmylua_check config"})
    else:
        severity = _as_dict(_as_dict(_read_json(emmy_path, jsonc=True).get("diagnostics")).get("severity"))
        absent = sorted(rule for rule in EMMY_REQUIRED_ERRORS if severity.get(rule) != "error")
        if absent:
            preview = ", ".join(absent[:MAX_RULE_PREVIEW])
            missing.append({"scope": "lua", "item": ".emmyrc.json severity", "detail": f"not error: {preview}"})
    if precommit_text and "luacheck" not in precommit_text:
        detail = "luacheck --only 561 --max-cyclomatic-complexity 10"
        missing.append({"scope": "lua", "item": "luacheck complexity hook", "detail": detail})
    return missing


def _missing_shell_nix_configs(stacks: dict[str, Any], *, precommit_text: str) -> list[dict[str, str]]:
    if not precommit_text:
        return []
    present: dict[str, int] = stacks["present"]
    checks: tuple[tuple[bool, str, str, str, str], ...] = (
        ("shell" in present, "shell", "shfmt", "shfmt hook", "format sh/bash scripts with shfmt -i 2"),
        ("shell" in present, "shell", "shellcheck", "shellcheck hook", "lint sh/bash scripts with shellcheck"),
        (bool(stacks["has_zsh"]), "shell", "zsh -n", "zsh syntax hook", "check zsh scripts with zsh -n"),
        ("nix" in present, "nix", "nixfmt", "nixfmt hook", "format Nix files with nixfmt"),
        ("nix" in present, "nix", "deadnix", "deadnix hook", "catch unused Nix bindings with deadnix --fail"),
        ("nix" in present, "nix", "statix", "statix hook", "catch Nix anti-patterns with statix check"),
    )
    return [
        {"scope": scope, "item": item, "detail": detail}
        for required, scope, needle, item, detail in checks
        if required and needle not in precommit_text
    ]


def _inspect_missing_configs(
    root: Path, stacks: dict[str, Any], *, files: list[str], package_json: dict[str, Any]
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
    missing.extend(_missing_setup_uv_pin(root))
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
    handlers = (
        ("python", lambda: _missing_python_configs(root, files, precommit_text=precommit_text)),
        ("web", lambda: _missing_web_configs(root, stacks, package_json=package_json)),
        ("rust", lambda: _missing_rust_configs(root)),
        ("go", lambda: _missing_go_configs(root, files)),
        ("lua", lambda: _missing_lua_configs(root, precommit_text=precommit_text)),
    )
    for stack, fn in handlers:
        if stack in present:
            missing.extend(fn())
    missing.extend(_missing_shell_nix_configs(stacks, precommit_text=precommit_text))
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
            if val in {"true", "false"}:
                return val == "true"
    return None


def _inspect_byor(root: Path, stacks: dict[str, Any]) -> dict[str, Any]:
    config_path = root / ".byor" / "config.yml"
    local_path = root / ".byor" / "local.yml"
    project_rules_dir = root / ".byor" / "rules" / "project"

    config_text = _read_text(config_path) or ""
    local_text = _read_text(local_path) or ""
    packages = _parse_simple_yaml_list(local_text, "packages") or _parse_simple_yaml_list(config_text, "packages")

    present = stacks["present"]
    expected = ["craft", *(stack for stack in ("python", "web") if stack in present)]

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
        if _is_fixture_path(rel) or Path(rel).suffix.lower() in SKIP_SIZE_EXTS or SKIP_SIZE_RE.search(rel):
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
            resolved, files, pyproject=pyproject, package_json=package_json, workflows=workflows
        ),
        "workflows": workflows,
        "missing_configs": _inspect_missing_configs(resolved, stacks, files=files, package_json=package_json),
        "byor": _inspect_byor(resolved, stacks),
        "tools": {tool: shutil.which(tool) is not None for tool in PARITY_TOOLS},
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


def _yn(flag: object) -> str:
    return "yes" if flag else "no"


def _md_table(title: str, header: str, *, rows: list[str], empty: str = "") -> list[str]:
    out = ["", f"## {title}", ""]
    if not rows:
        return [*out, empty]
    sep = "| " + " | ".join("---" for _ in header.strip("|").split("|")) + " |"
    return [*out, header, sep, *rows]


def format_markdown(report: dict[str, Any]) -> str:
    """Format an audit report as concise Markdown tables."""
    lines: list[str] = [f"# Repository audit: `{report['path']}`", "", *_format_stacks_section(report["stacks"])]
    legacy_rows = [
        f"| {e['category']} | {e['tool']} | {', '.join(f'`{ev}`' for ev in e['evidence'])} |"
        for e in report["legacy_tooling"]
    ]
    lines.extend(
        _md_table("Legacy tooling", "| Category | Tool | Evidence |", rows=legacy_rows, empty="None detected.")
    )
    lines.extend(["", *_format_workflows_section(report["workflows"])])
    missing_rows = [f"| {m['scope']} | `{m['item']}` | {m['detail']} |" for m in report["missing_configs"]]
    no_missing = "All canonical files and configs are present."
    lines.extend(
        _md_table(
            "Missing canonical files and configs", "| Scope | Missing | Why |", rows=missing_rows, empty=no_missing
        )
    )
    byor = report["byor"]
    byor_rows = [
        f"| Initialized (`.byor/`) | {_yn(byor['initialized'])} |",
        f"| Enabled packages | {', '.join(byor['packages']) or 'none'} |",
        f"| Expected packages | {', '.join(byor['expected_packages'])} |",
        f"| Missing packages | {', '.join(byor['missing_packages']) or 'none'} |",
        f"| Stale packages | {', '.join(byor['stale_packages']) or 'none'} |",
        f"| `gate: true` set (should be false) | {_yn(byor['gate_enabled'])} |",
        f"| Project rules (`.byor/rules/project/`) | {byor['project_rules_count']} |",
        f"| Needs `ast-grep` prek hook | {_yn(byor['needs_ast_grep_hook'])} |",
    ]
    lines.extend(_md_table("BYOR wiring", "| Check | Status |", rows=byor_rows))
    lines.extend(["", *_format_sizes_section(report["file_sizes"])])
    tool_rows = [f"| `{n}` | {_yn(ok)} |" for n, ok in report["tools"].items()]
    lines.extend(_md_table("Local tools", "| Tool | Available |", rows=tool_rows))
    h = report["git_hygiene"]
    h_rows = [
        f"| `.git-blame-ignore-revs` | {_yn(h['has_git_blame_ignore_revs'])} |",
        f"| `BACKLOG.md` | {_yn(h['has_backlog_md'])} |",
        f"| `AGENTS.md` | {_yn(h['has_agents_md'])} |",
        f"| `README.md` | {_yn(h['has_readme_md'])} |",
    ]
    lines.extend(_md_table("Git hygiene", "| File | Present |", rows=h_rows))
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
