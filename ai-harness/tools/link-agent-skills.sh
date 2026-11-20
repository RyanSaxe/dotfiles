#!/bin/sh
# Links each skill in ~/.agents/skills, the folder Codex reads, into
# ~/.claude/skills and ~/.gemini/config/skills, which Claude Code and
# Antigravity CLI read. A name an agent already has stays as it is, and a
# link made here goes when its skill does.
from="$HOME/.agents/skills"

sync_dir() {
  to="$1"
  mkdir -p "$to"

  for skill in "$from"/*/; do
    [ -d "$skill" ] || continue
    name=$(basename "$skill")
    case $name in
    # Home Manager's backups, such as NAME.pre-nix, aren't skills.
    *.pre-nix) continue ;;
    esac
    [ -f "$skill/SKILL.md" ] || continue
    [ -e "$to/$name" ] || [ -L "$to/$name" ] || ln -s "$from/$name" "$to/$name"
  done

  for link in "$to"/*; do
    [ -L "$link" ] || continue
    case $(readlink "$link") in
    "$from"/*) [ -e "$link" ] || rm "$link" ;;
    esac
  done
}

sync_dir "$HOME/.claude/skills"
sync_dir "$HOME/.gemini/config/skills"
