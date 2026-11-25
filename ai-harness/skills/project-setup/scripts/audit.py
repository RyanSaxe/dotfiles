#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# dependencies = []
# ///
"""Read-only repository audit CLI entrypoint for the project-setup skill."""

from __future__ import annotations

import argparse
import json
import shutil
import sys
from pathlib import Path
from typing import Any

from audit_checks import inspect_missing_configs
from audit_io import list_repo_files, read_json, read_toml
from audit_report import format_markdown
from audit_stacks import (
    PARITY_TOOLS,
    detect_stacks,
    inspect_byor,
    inspect_file_sizes,
    inspect_legacy_tooling,
    inspect_workflows,
)


def audit_repository(root: Path) -> dict[str, Any]:
    resolved = root.resolve()
    files, is_git_repo = list_repo_files(resolved)
    pyproject = read_toml(resolved / "pyproject.toml")
    package_json = read_json(resolved / "package.json")
    stacks = detect_stacks(resolved, files, package_json=package_json)
    workflows = inspect_workflows(resolved)
    return {
        "path": str(resolved),
        "is_git_repo": is_git_repo,
        "total_files": len(files),
        "stacks": stacks,
        "legacy_tooling": inspect_legacy_tooling(
            resolved, files, pyproject=pyproject, package_json=package_json, workflows=workflows
        ),
        "workflows": workflows,
        "missing_configs": inspect_missing_configs(resolved, stacks, files=files, package_json=package_json),
        "byor": inspect_byor(resolved, stacks),
        "tools": {tool: shutil.which(tool) is not None for tool in PARITY_TOOLS},
        "file_sizes": inspect_file_sizes(resolved, files),
        "git_hygiene": {
            "has_git_blame_ignore_revs": (resolved / ".git-blame-ignore-revs").is_file(),
            "has_backlog_md": (resolved / "BACKLOG.md").is_file(),
            "has_agents_md": (resolved / "AGENTS.md").is_file(),
            "has_readme_md": (resolved / "README.md").is_file(),
        },
    }


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
