from __future__ import annotations

import json
import re
import subprocess
from pathlib import Path
from typing import Any

REPO = Path(__file__).resolve().parents[2]
AUDIT_SCRIPT = REPO / "ai-harness/skills/project-setup/scripts/audit.py"
EMMYRC_TEMPLATE = REPO / "ai-harness/skills/project-setup/templates/emmyrc.json"
OXLINTRC_TEMPLATE = REPO / "ai-harness/skills/project-setup/templates/oxlintrc.json"
JSONC_TOKEN_RE = re.compile(r'"(?:\\.|[^"\\])*"|//[^\n]*|/\*.*?\*/', re.DOTALL)


def _parse_jsonc(path: Path) -> dict[str, Any]:
    text = path.read_text(encoding="utf-8")
    stripped = JSONC_TOKEN_RE.sub(lambda m: m.group(0) if m.group(0).startswith('"') else "", text)
    return json.loads(stripped)


def _run_audit(target: Path) -> dict[str, Any]:
    result = subprocess.run(
        ["uv", "run", "--no-project", str(AUDIT_SCRIPT), "--json", str(target)],
        capture_output=True,
        text=True,
        check=True,
        timeout=15,
    )
    return json.loads(result.stdout)


def test_emmyrc_template_is_strict_json_and_catches_errors(tmp_path: Path) -> None:
    parsed = json.loads(EMMYRC_TEMPLATE.read_text(encoding="utf-8"))
    assert parsed["diagnostics"]["severity"]["param-type-mismatch"] == "error"

    cfg = tmp_path / ".emmyrc.json"
    cfg.write_text(EMMYRC_TEMPLATE.read_text(encoding="utf-8"), encoding="utf-8")
    (tmp_path / "bad.lua").write_text(
        '---@param x integer\nlocal function f(x)\n  local unused_var = 1\n  return x\nend\nf("bad")\n',
        encoding="utf-8",
    )
    res = subprocess.run(
        ["emmylua_check", "-c", str(cfg), "--severity", "error", str(tmp_path)],
        capture_output=True,
        text=True,
        check=False,
        timeout=10,
    )
    output = res.stdout + res.stderr
    assert res.returncode == 1
    assert "param-type-mismatch" in output
    assert "unused" in output


def test_audit_accepts_stricter_python_complexity_and_flags_unpinned_setup_uv(tmp_path: Path) -> None:
    (tmp_path / "pyproject.toml").write_text(
        '[project]\nname = "demo"\nversion = "0.1.0"\n'
        '[dependency-groups]\ndev = ["ty"]\n'
        '[tool.ruff.lint]\nselect = ["ALL"]\n'
        "[tool.ruff.lint.mccabe]\nmax-complexity = 6\n"
        "[tool.ruff.lint.pylint]\nmax-positional-args = 2\nmax-branches = 8\nmax-nested-blocks = 3\n"
        '[tool.ruff.lint.flake8-tidy-imports.banned-api]\n"typing.cast".msg = "no cast"\n',
        encoding="utf-8",
    )
    (tmp_path / "uv.lock").write_text("", encoding="utf-8")
    wf = tmp_path / ".github/workflows"
    wf.mkdir(parents=True)
    (wf / "check.yml").write_text(
        "jobs:\n  check:\n    steps:\n      - uses: astral-sh/setup-uv@v6\n",
        encoding="utf-8",
    )

    report = _run_audit(tmp_path)
    missing_items = {entry["item"] for entry in report["missing_configs"]}
    assert not any("max-complexity" in item or "max-branches" in item for item in missing_items)
    assert not any("max-nested-blocks" in item for item in missing_items)
    assert "check.yml setup-uv semver pin" in missing_items

    (wf / "check.yml").write_text(
        "jobs:\n  check:\n    steps:\n      - uses: astral-sh/setup-uv@v10.4.0\n",
        encoding="utf-8",
    )
    pinned_report = _run_audit(tmp_path)
    pinned_items = {entry["item"] for entry in pinned_report["missing_configs"]}
    assert "check.yml setup-uv semver pin" not in pinned_items


def test_audit_only_expects_zsh_hook_when_zsh_scripts_exist(tmp_path: Path) -> None:
    (tmp_path / ".pre-commit-config.yaml").write_text("shfmt\nshellcheck\nmax-file-lines\n", encoding="utf-8")
    (tmp_path / "tool.sh").write_text("#!/bin/sh\necho ok\n", encoding="utf-8")

    sh_only = _run_audit(tmp_path)
    sh_items = {entry["item"] for entry in sh_only["missing_configs"]}
    assert "zsh syntax hook" not in sh_items

    (tmp_path / "helper.sh").write_text("#!/usr/bin/env zsh\necho ok\n", encoding="utf-8")
    with_zsh = _run_audit(tmp_path)
    zsh_items = {entry["item"] for entry in with_zsh["missing_configs"]}
    assert "zsh syntax hook" in zsh_items


def test_audit_detects_nested_golangci_empty_oxlint_and_selene(tmp_path: Path) -> None:
    go_mod = tmp_path / "pkgs/ws"
    go_mod.mkdir(parents=True)
    (go_mod / "go.mod").write_text("module example.com/ws\n", encoding="utf-8")
    (go_mod / "main.go").write_text("package main\nfunc main() {}\n", encoding="utf-8")
    (go_mod / ".golangci.yml").write_text(
        "linters:\n  enable: [cyclop, gocognit, nestif, revive, gosec, errcheck, errorlint, staticcheck, gofumpt]\n",
        encoding="utf-8",
    )
    (tmp_path / "package.json").write_text(
        '{"devDependencies": {"oxlint": "1.0.0", "oxfmt": "1.0.0"}}', encoding="utf-8"
    )
    (tmp_path / ".oxlintrc.json").write_text("{}\n", encoding="utf-8")
    (tmp_path / "selene.toml").write_text('std = "lua54"\n', encoding="utf-8")
    (tmp_path / "init.lua").write_text("local x = 1\nreturn x\n", encoding="utf-8")

    report = _run_audit(tmp_path)
    missing_items = {entry["item"] for entry in report["missing_configs"]}
    assert ".golangci.yml" not in missing_items
    assert ".oxlintrc.json parity rules" in missing_items
    legacy = {(entry["category"], entry["tool"]) for entry in report["legacy_tooling"]}
    assert ("lua", "selene") in legacy


def test_oxlintrc_template_is_valid_jsonc_and_enforces_react_useeffect_boundary() -> None:
    parsed = _parse_jsonc(OXLINTRC_TEMPLATE)
    rule = parsed["rules"]["no-restricted-imports"]
    assert rule[0] == "error"
    react_paths = [entry for entry in rule[1]["paths"] if entry["name"] == "react"]
    assert len(react_paths) == 1
    assert set(react_paths[0]["importNames"]) == {"useEffect", "useLayoutEffect"}

    overrides = parsed["overrides"]
    hooks_overrides = [ov for ov in overrides if "**/hooks/**" in ov["files"]]
    assert len(hooks_overrides) == 1
    assert hooks_overrides[0]["rules"]["no-restricted-imports"] == "off"


def test_audit_checks_react_oxlint_plugins_and_restricted_imports(tmp_path: Path) -> None:
    (tmp_path / "package.json").write_text(
        json.dumps(
            {
                "dependencies": {"react": "19.2.0"},
                "devDependencies": {"oxlint": "1.0.0", "oxfmt": "1.0.0", "oxlint-tsgolint": "1.0.0"},
            }
        ),
        encoding="utf-8",
    )
    (tmp_path / "package-lock.json").write_text("{}\n", encoding="utf-8")
    (tmp_path / ".oxfmtrc.json").write_text("{}\n", encoding="utf-8")
    (tmp_path / "App.tsx").write_text("export function App() { return <div />; }\n", encoding="utf-8")

    # Copy template without enabling react/jsx-a11y plugins yet.
    (tmp_path / ".oxlintrc.json").write_text(OXLINTRC_TEMPLATE.read_text(encoding="utf-8"), encoding="utf-8")
    before = _run_audit(tmp_path)
    before_items = {entry["item"]: entry["detail"] for entry in before["missing_configs"]}
    assert ".oxlintrc.json parity rules" not in before_items
    assert ".oxlintrc.json React plugins" in before_items
    assert "react" in before_items[".oxlintrc.json React plugins"]
    assert "jsx-a11y" in before_items[".oxlintrc.json React plugins"]

    # Enable react + jsx-a11y plugins; React oxlint audit checks should now pass.
    updated = _parse_jsonc(OXLINTRC_TEMPLATE)
    updated["plugins"] = [*updated["plugins"], "react", "jsx-a11y"]
    (tmp_path / ".oxlintrc.json").write_text(json.dumps(updated, indent=2), encoding="utf-8")
    after = _run_audit(tmp_path)
    after_items = {entry["item"] for entry in after["missing_configs"]}
    assert ".oxlintrc.json parity rules" not in after_items
    assert ".oxlintrc.json React plugins" not in after_items
