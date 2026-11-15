#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# ///
"""Writes a Claude Code agent in ~/.claude/agents for each Codex agent in
~/.codex/agents, and removes the ones whose Codex agent is gone.

A file this script didn't write stays as it is, so an agent made for Claude
by hand or by another installer wins over a Codex agent of the same name.
"""

import json
import tomllib
from pathlib import Path

CODEX_AGENTS = Path.home() / ".codex" / "agents"
CLAUDE_AGENTS = Path.home() / ".claude" / "agents"
MARK = "# Written by convert-codex-agents.py from ~/.codex/agents/{name}.toml."


def claude_agent(name: str, description: str, instructions: str) -> str:
    # JSON strings are valid YAML scalars, so this quotes any description.
    return (
        f"---\n{MARK.format(name=name)}\n"
        f"name: {json.dumps(name)}\n"
        f"description: {json.dumps(description)}\n"
        f"---\n\n{instructions.strip()}\n"
    )


def written_here(path: Path) -> bool:
    return path.read_text().startswith(f"---\n{MARK.format(name=path.stem)}\n")


def main() -> None:
    CLAUDE_AGENTS.mkdir(parents=True, exist_ok=True)
    converted = set()
    for source in sorted(CODEX_AGENTS.glob("*.toml")):
        agent = tomllib.loads(source.read_text())
        name = agent["name"]
        target = CLAUDE_AGENTS / f"{name}.md"
        if target.exists() and not written_here(target):
            continue
        text = claude_agent(name, agent["description"], agent["developer_instructions"])
        if not target.exists() or target.read_text() != text:
            target.write_text(text)
        converted.add(target)

    for target in CLAUDE_AGENTS.glob("*.md"):
        if target not in converted and written_here(target):
            target.unlink()


if __name__ == "__main__":
    main()
