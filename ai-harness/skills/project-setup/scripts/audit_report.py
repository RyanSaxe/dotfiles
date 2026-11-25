"""Markdown report formatter for repository audit results."""

from __future__ import annotations

from typing import Any


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
    if flag:
        return "yes"
    return "no"


def _md_table(title: str, header: str, *, rows: list[str], empty: str = "") -> list[str]:
    out = ["", f"## {title}", ""]
    if not rows:
        return [*out, empty]
    sep = "| " + " | ".join("---" for _ in header.strip("|").split("|")) + " |"
    return [*out, header, sep, *rows]


def format_markdown(report: dict[str, Any]) -> str:
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
