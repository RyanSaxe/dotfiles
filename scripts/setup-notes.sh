#!/usr/bin/env bash
set -euo pipefail

# Bootstrap the Obsidian vault used by the Neovim config.
#
# Behavior:
#   - If the vault path already exists, leave it completely unchanged.
#   - If it does not exist, try to clone the private notes repo.
#   - If cloning fails, create a minimal fresh vault with the expected shape.
#
# Configuration:
#   NOTES_DIR           Defaults to "$HOME/generic/notes"
#   PRIVATE_NOTES_REPO  Defaults to "git@github.com:RyanSaxe/notes.git"

NOTES_DIR="${NOTES_DIR:-$HOME/generic/notes}"
PRIVATE_REPO_URL="${PRIVATE_NOTES_REPO:-git@github.com:RyanSaxe/notes.git}"

usage() {
  echo "Usage: $0"
  echo ""
  echo "Bootstraps the Obsidian vault if it does not already exist."
  echo ""
  echo "Environment:"
  echo "  NOTES_DIR           Vault path. Default: \$HOME/generic/notes"
  echo "  PRIVATE_NOTES_REPO  Git URL to clone first."
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "Error: Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -e "$NOTES_DIR" ]]; then
  echo "Notes path already exists; leaving it unchanged: $NOTES_DIR"
  exit 0
fi

write_file_once() {
  local path="$1"
  mkdir -p "$(dirname "$path")"

  if [[ -e "$path" ]]; then
    return
  fi

  cat > "$path"
}

clone_private_repo() {
  local parent_dir
  local clone_dir

  parent_dir="$(dirname "$NOTES_DIR")"
  mkdir -p "$parent_dir"
  clone_dir="$(mktemp -d "$parent_dir/.notes-clone.XXXXXX")"

  echo "Cloning private notes repository..."
  echo "  Repository: $PRIVATE_REPO_URL"
  echo "  Destination: $NOTES_DIR"

  if git clone "$PRIVATE_REPO_URL" "$clone_dir"; then
    mv "$clone_dir" "$NOTES_DIR"
    echo "Cloned private notes repository."
    return 0
  fi

  rm -rf "$clone_dir"
  return 1
}

create_basic_vault() {
  echo "Creating basic notes vault..."

  mkdir -p \
    "$NOTES_DIR/daily" \
    "$NOTES_DIR/people" \
    "$NOTES_DIR/projects" \
    "$NOTES_DIR/sources" \
    "$NOTES_DIR/wiki" \
    "$NOTES_DIR/templates" \
    "$NOTES_DIR/assets"

  write_file_once "$NOTES_DIR/templates/daily.md" << 'EOF'
# {{date}}

## Today

- [ ]

## Log

## Notes

## Links
EOF

  write_file_once "$NOTES_DIR/templates/person.md" << 'EOF'
---
aliases: []
---

# {{title}}

## Context

## Current

## Log
EOF

  write_file_once "$NOTES_DIR/AGENTS.md" << 'EOF'
# Vault Instructions

This vault separates working notes from durable synthesis.

## Human Notes

- `daily/`, `people/`, and `projects/` are human-authored working notes.
- Do not rewrite these notes unless explicitly asked.
- Prefer small edits, added links, and appended context over broad rewrites.

## Sources

- `sources/` stores raw or semi-raw inputs: articles, transcripts, research, copied context, and AI session outputs.
- Preserve original meaning.
- Summaries are allowed, but source notes do not need to be polished wiki pages.

## Wiki

- `wiki/` is the AI-maintained synthesis layer.
- Wiki pages should explain durable concepts, tools, decisions, systems, and things worth reusing.
- Create or update wiki pages when source material teaches something reusable.
- Use subfolders when they help, but do not force a taxonomy up front.
- Link related wiki pages.
- Cite source notes when possible.
- Update `wiki/index.md` when adding an important wiki page.
EOF

  write_file_once "$NOTES_DIR/wiki/index.md" << 'EOF'
# Wiki

Durable AI-maintained synthesis starts here.
EOF

  write_file_once "$NOTES_DIR/.gitignore" << 'EOF'
.obsidian/workspace.json
.obsidian/workspace-mobile.json
.DS_Store
.nvim.lua
EOF

  echo "Created basic notes vault: $NOTES_DIR"
}

if clone_private_repo; then
  exit 0
fi

echo "Clone failed; falling back to a basic local vault."
create_basic_vault
