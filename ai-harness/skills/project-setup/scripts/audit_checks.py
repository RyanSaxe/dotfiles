"""Canonical configuration and cross-language parity checks for the repository audit."""

from __future__ import annotations

import re
from pathlib import Path
from typing import Any

from audit_io import (
    as_dict,
    collect_node_deps,
    collect_python_deps,
    is_template_or_fixture_path,
    read_json,
    read_text,
    read_toml,
)

EXPECTED_MAX_POSITIONAL_ARGS = 2
EXPECTED_MAX_COMPLEXITY = 8
EXPECTED_MAX_BRANCHES = 10
EXPECTED_MAX_NESTED_BLOCKS = 4
MAX_RULE_PREVIEW = 4

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
SETUP_UV_RE = re.compile(r"astral-sh/setup-uv(?:@([^\s'\"#]+))?")
SEMVER_PIN_RE = re.compile(r"v?\d+\.\d+\.\d+")
TY_CHECK_RE = re.compile(r"\bty(?:@[^\s]+)?\s+check\b")


def _within_cap(value: object, limit: int) -> bool:
    if isinstance(value, bool) or not isinstance(value, int):
        return False
    return 1 <= value <= limit


def _missing_ruff_rules(ruff_cfg: dict[str, Any], *, table_prefix: str = "tool.ruff.") -> list[dict[str, str]]:
    if not ruff_cfg:
        section = f"[{table_prefix.rstrip('.')}]" if table_prefix else "ruff.toml"
        return [{"scope": "python", "item": section, "detail": "Ruff config in pyproject.toml"}]
    lint_cfg = as_dict(ruff_cfg.get("lint"))
    pylint_cfg = as_dict(lint_cfg.get("pylint"))
    mccabe_cfg = as_dict(lint_cfg.get("mccabe"))
    caps = (
        (mccabe_cfg, "mccabe", "max-complexity", EXPECTED_MAX_COMPLEXITY, "cap cyclomatic complexity via C901"),
        (pylint_cfg, "pylint", "max-positional-args", EXPECTED_MAX_POSITIONAL_ARGS, "cap positional args via PLR0917"),
        (pylint_cfg, "pylint", "max-branches", EXPECTED_MAX_BRANCHES, "cap branches via PLR0912"),
        (pylint_cfg, "pylint", "max-nested-blocks", EXPECTED_MAX_NESTED_BLOCKS, "cap nesting depth via PLR1702"),
    )
    checks = [
        (lint_cfg.get("select") != ["ALL"], f"[{table_prefix}lint] select = ['ALL']", "enable Ruff ALL ruleset"),
        *(
            (not _within_cap(cfg.get(key), limit), f"[{table_prefix}lint.{sec}] {key} <= {limit}", detail)
            for cfg, sec, key, limit, detail in caps
        ),
        (
            not as_dict(as_dict(lint_cfg.get("flake8-tidy-imports")).get("banned-api")),
            f"[{table_prefix}lint.flake8-tidy-imports.banned-api]",
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
        text = read_text(path) or ""
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


def _has_ty_hook(precommit_text: str) -> bool:
    if "ty-pre-commit" in precommit_text:
        return True
    return bool(TY_CHECK_RE.search(precommit_text))


def _missing_python_project_configs(proj_dir: Path, root: Path, *, precommit_text: str) -> list[dict[str, str]]:
    prefix = "" if proj_dir == root else f"{proj_dir.relative_to(root).as_posix()}/"
    pyproject = read_toml(proj_dir / "pyproject.toml")
    missing: list[dict[str, str]] = []
    if not (proj_dir / "uv.lock").is_file():
        missing.append({"scope": "python", "item": f"{prefix}uv.lock", "detail": "committed uv lockfile"})
    missing.extend(
        {**entry, "item": f"{prefix}{entry['item']}"}
        for entry in _missing_ruff_rules(as_dict(as_dict(pyproject.get("tool")).get("ruff")))
    )
    if "ty" not in collect_python_deps(proj_dir, pyproject) and not _has_ty_hook(precommit_text):
        detail = "add ty to dev deps and .pre-commit-config.yaml"
        missing.append({"scope": "python", "item": f"{prefix}ty", "detail": detail})
    return missing


def _missing_standalone_ruff_configs(ruff_path: Path, *, precommit_text: str) -> list[dict[str, str]]:
    missing = _missing_ruff_rules(read_toml(ruff_path), table_prefix="")
    if not _has_ty_hook(precommit_text):
        missing.append({"scope": "python", "item": "ty", "detail": "add ty hook to .pre-commit-config.yaml"})
    return missing


def _missing_python_configs(root: Path, files: list[str], *, precommit_text: str) -> list[dict[str, str]]:
    proj_dirs = (
        [root]
        if (root / "pyproject.toml").is_file()
        else sorted(
            {
                root / Path(r).parent
                for r in files
                if not is_template_or_fixture_path(r) and Path(r).name == "pyproject.toml"
            }
        )
    )
    if not proj_dirs:
        ruff_path = next((p for name in ("ruff.toml", ".ruff.toml") if (p := root / name).is_file()), None)
        has_legacy_pkg = (root / "setup.py").is_file() or any(root.glob("requirements*.txt"))
        if ruff_path is not None and not has_legacy_pkg:
            return _missing_standalone_ruff_configs(ruff_path, precommit_text=precommit_text)
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
    cfg = read_json(root / ".oxlintrc.json", jsonc=True)
    rules = as_dict(cfg.get("rules"))
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
    node_deps = collect_node_deps(package_json)
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
    cargo = read_toml(root / "Cargo.toml")
    clippy_cfg = as_dict(as_dict(cargo.get("lints")).get("clippy")) or as_dict(
        as_dict(as_dict(cargo.get("workspace")).get("lints")).get("clippy")
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
    for directory in (mod_dir, Path()):
        for name in (".golangci.yml", ".golangci.yaml"):
            candidate = root / directory / name
            if candidate.is_file():
                return candidate
    return None


def _missing_go_configs(root: Path, files: list[str]) -> list[dict[str, str]]:
    mod_dirs = sorted(
        {Path(rel).parent for rel in files if not is_template_or_fixture_path(rel) and Path(rel).name == "go.mod"}
    ) or [Path()]
    missing: list[dict[str, str]] = []
    for mod_dir in mod_dirs:
        cfg_path = _find_golangci_cfg(root, mod_dir)
        if cfg_path is None:
            item = ".golangci.yml" if mod_dir == Path() else f"{mod_dir.as_posix()}/.golangci.yml"
            missing.append({"scope": "go", "item": item, "detail": "golangci-lint v2 config"})
            continue
        text = read_text(cfg_path) or ""
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
        severity = as_dict(as_dict(read_json(emmy_path, jsonc=True).get("diagnostics")).get("severity"))
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


def inspect_missing_configs(
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
    precommit_text = read_text(root / ".pre-commit-config.yaml") or ""
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
