#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# ///
"""Convert Codex agents into Claude Code and Antigravity agent definitions.

Writes Claude Code agents in ~/.claude/agents and Antigravity agents in
~/.gemini/config/agents for each Codex agent in ~/.codex/agents, and removes
the ones whose Codex agent is gone.

A file this script didn't write stays as it is, so an agent made by hand or
by another installer wins over a Codex agent of the same name.
"""

from __future__ import annotations

import json
import tomllib
from pathlib import Path
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from collections.abc import Callable

CODEX_AGENTS = Path.home() / ".codex" / "agents"
CLAUDE_AGENTS = Path.home() / ".claude" / "agents"
ANTIGRAVITY_AGENTS = Path.home() / ".gemini" / "config" / "agents"
MARK = "# Written by convert-codex-agents.py from ~/.codex/agents/{name}.toml."


def claude_agent(name: str, *, description: str, instructions: str) -> str:
    # JSON strings are valid YAML scalars, so this quotes any description.
    return (
        f"---\n{MARK.format(name=name)}\n"
        f"name: {json.dumps(name)}\n"
        f"description: {json.dumps(description)}\n"
        f"---\n\n{instructions.strip()}\n"
    )


def antigravity_agent(name: str, *, description: str, instructions: str) -> str:
    return (
        f"---\n{MARK.format(name=name)}\n"
        f"name: {json.dumps(name)}\n"
        f"description: {json.dumps(description)}\n"
        "mainAgent: true\n"
        "subagent: true\n"
        "tools:\n"
        "  - read_file\n"
        "  - write_file\n"
        "  - edit_file\n"
        "  - run_command\n"
        "  - search_web\n"
        f"---\n\n{instructions.strip()}\n"
    )


def written_here(path: Path) -> bool:
    if path.is_symlink() or not path.is_file():
        return False
    return path.read_text().startswith(f"---\n{MARK.format(name=path.stem)}\n")


def sync_target(target_dir: Path, agents: list[dict[str, str]], *, render: Callable[..., str]) -> None:
    target_dir.mkdir(parents=True, exist_ok=True)
    converted: set[Path] = set()
    for agent in agents:
        name = agent["name"]
        target = target_dir / f"{name}.md"
        if target.is_symlink() or (target.exists() and not written_here(target)):
            continue
        text = render(name, description=agent["description"], instructions=agent["developer_instructions"])
        if not target.exists() or target.read_text() != text:
            target.write_text(text)
        converted.add(target)

    for target in target_dir.glob("*.md"):
        if target not in converted and written_here(target):
            target.unlink()


def main() -> None:
    agents = [tomllib.loads(source.read_text()) for source in sorted(CODEX_AGENTS.glob("*.toml")) if source.is_file()]
    sync_target(CLAUDE_AGENTS, agents, render=claude_agent)
    sync_target(ANTIGRAVITY_AGENTS, agents, render=antigravity_agent)


if __name__ == "__main__":
    main()
