"""Stack, workflow, legacy tooling, BYOR, file-size, and git-hygiene detectors."""

from __future__ import annotations

import re
from pathlib import Path
from typing import Any

from audit_io import (
    as_dict,
    collect_node_deps,
    collect_python_deps,
    is_fixture_path,
    is_template_or_fixture_path,
    parse_simple_yaml_bool,
    parse_simple_yaml_list,
    read_ini_sections,
    read_text,
)

WARNING_LINE_THRESHOLD = 600
HARD_CAP_LINE_THRESHOLD = 1000
PARITY_TOOLS = ("shellcheck", "shfmt", "deadnix", "statix", "luacheck")

ZSH_SHEBANG_RE = re.compile(rb"^#!\s*(?:/\S*/)?(?:env\s+(?:-\S+\s+)*)?zsh(?:\s|$)")
NODE_SHEBANG_RE = re.compile(rb"^#!\s*(?:/\S*/)?(?:env\s+(?:-\S+\s+)*)?node(?:\s|$)")
NODE_SCRIPT_EXTS = frozenset({".js", ".mjs", ".cjs"})

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


def _read_first_line(path: Path) -> bytes:
    try:
        with path.open("rb") as handle:
            return handle.readline(256)
    except OSError:
        return b""


def _is_standalone_node_script(root: Path, rel: str) -> bool:
    if Path(rel).suffix.lower() not in NODE_SCRIPT_EXTS:
        return False
    return bool(NODE_SHEBANG_RE.match(_read_first_line(root / rel)))


def _has_zsh_files(root: Path, files: list[str]) -> bool:
    for rel in files:
        path = Path(rel)
        suffix = path.suffix.lower()
        if suffix == ".zsh" or path.name in {"zshrc", "zshrc.minimal", ".zshrc"}:
            return True
        if suffix in {".sh", ".bash", ""} and ZSH_SHEBANG_RE.match(_read_first_line(root / rel)):
            return True
    return False


def detect_stacks(root: Path, files: list[str], *, package_json: dict[str, Any]) -> dict[str, Any]:
    source_files = [rel for rel in files if not is_fixture_path(rel)]
    has_package_json = (root / "package.json").is_file()
    counts: dict[str, int] = dict.fromkeys(STACK_EXTS, 0)
    ts_count = 0
    react_count = 0
    for rel in source_files:
        ext = Path(rel).suffix.lower()
        for stack, exts in STACK_EXTS.items():
            if ext not in exts:
                continue
            if stack == "web" and not has_package_json and _is_standalone_node_script(root, rel):
                continue
            counts[stack] += 1
        ts_count += int(ext in TS_EXTS)
        react_count += int(ext in REACT_EXTS)

    node_deps = collect_node_deps(package_json)
    project_files = [rel for rel in files if not is_template_or_fixture_path(rel)]
    has_python_marker = (
        (root / "pyproject.toml").is_file()
        or (root / "setup.py").is_file()
        or any(root.glob("requirements*.txt"))
        or any(Path(rel).name == "pyproject.toml" for rel in project_files)
    )
    markers = {
        "python": has_python_marker,
        "web": has_package_json,
        "markdown": False,
        "rust": (root / "Cargo.toml").is_file(),
        "go": (root / "go.mod").is_file() or any(Path(rel).name == "go.mod" for rel in project_files),
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
    text = read_text(path) or ""
    entry = {
        "path": path.relative_to(root).as_posix(),
        "jobs": _parse_workflow_jobs(text),
        "legacy_tools": [name for name, pat in WORKFLOW_LEGACY_PATTERNS if pat.search(text)],
    }
    return entry, bool(re.search(r"\bprek\b", text))


def inspect_workflows(root: Path) -> dict[str, Any]:
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


def _legacy_python_tools(root: Path, pyproject: dict[str, Any]) -> list[dict[str, Any]]:
    py_deps = collect_python_deps(root, pyproject)
    py_tools = as_dict(pyproject.get("tool"))
    ini_sections = read_ini_sections(root)
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
    node_deps = collect_node_deps(package_json)
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


def inspect_legacy_tooling(
    root: Path,
    files: list[str],
    *,
    pyproject: dict[str, Any],
    package_json: dict[str, Any],
    workflows: dict[str, Any],
) -> list[dict[str, Any]]:
    findings = _legacy_python_tools(root, pyproject)
    findings.extend(_legacy_web_tools(root, files, package_json=package_json))

    node_deps = collect_node_deps(package_json)
    mdlint_ev = [rel for rel in files if Path(rel).name.startswith(".markdownlint")]
    mdlint_ev.extend(f"package.json-dep:{dep}" for dep in node_deps if "markdownlint" in dep)
    if mdlint_ev:
        findings.append({"category": "markdown", "tool": "markdownlint", "evidence": sorted(set(mdlint_ev))})
    findings.extend(_legacy_lua_tools(root, files, workflows=workflows))

    precommit_ev: list[str] = []
    if "pre-commit" in collect_python_deps(root, pyproject):
        precommit_ev.append("python-dep:pre-commit")
    precommit_ev.extend(f"{wf['path']}:pre-commit" for wf in workflows["files"] if "pre-commit" in wf["legacy_tools"])
    git_hook = root / ".git" / "hooks" / "pre-commit"
    if git_hook.is_file() and "prek" not in (read_text(git_hook) or "").lower():
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


def inspect_byor(root: Path, stacks: dict[str, Any]) -> dict[str, Any]:
    config_path = root / ".byor" / "config.yml"
    local_path = root / ".byor" / "local.yml"
    project_rules_dir = root / ".byor" / "rules" / "project"

    config_text = read_text(config_path) or ""
    local_text = read_text(local_path) or ""
    packages = parse_simple_yaml_list(local_text, "packages") or parse_simple_yaml_list(config_text, "packages")

    present = stacks["present"]
    expected = ["craft", *(stack for stack in ("python", "web") if stack in present)]

    project_rules: list[str] = []
    if project_rules_dir.is_dir():
        project_rules = sorted(
            path.relative_to(root).as_posix()
            for path in [*project_rules_dir.rglob("*.yml"), *project_rules_dir.rglob("*.yaml")]
            if path.is_file()
        )

    precommit_text = read_text(root / ".pre-commit-config.yaml") or ""
    enabled_set = set(packages)
    return {
        "initialized": config_path.is_file() or local_path.is_file(),
        "has_config_yml": config_path.is_file(),
        "has_local_yml": local_path.is_file(),
        "packages": packages,
        "expected_packages": expected,
        "missing_packages": [pkg for pkg in expected if pkg not in enabled_set],
        "stale_packages": [pkg for pkg in packages if pkg == "style"],
        "gate_enabled": parse_simple_yaml_bool(config_text, "gate") is True,
        "project_rules": project_rules,
        "project_rules_count": len(project_rules),
        "needs_ast_grep_hook": len(project_rules) > 0 and "ast-grep" not in precommit_text,
    }


def inspect_file_sizes(root: Path, files: list[str]) -> dict[str, Any]:
    warning: list[dict[str, Any]] = []
    hard_cap: list[dict[str, Any]] = []
    for rel in files:
        if is_fixture_path(rel) or Path(rel).suffix.lower() in SKIP_SIZE_EXTS or SKIP_SIZE_RE.search(rel):
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
