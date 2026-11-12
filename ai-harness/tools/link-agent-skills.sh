#!/bin/sh
# Links each skill in ~/.agents/skills, the folder Codex reads, into
# ~/.claude/skills, the only folder Claude Code reads.
# A name Claude already has stays as it is, and a link made here goes when
# its skill does.
from="$HOME/.agents/skills"
to="$HOME/.claude/skills"
mkdir -p "$to"

for skill in "$from"/*/; do
  name=$(basename "$skill")
  case $name in
  # Home Manager's backups, such as unslop.pre-nix, aren't skills.
  *.*) continue ;;
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
