#!/usr/bin/env bash
set -euo pipefail

# Setup Obsidian notes scaffolding for Neovim integration
#
# This script creates the necessary folder structure and templates for
# Obsidian notes to work with the obsidian.nvim plugin configuration.
#
# Usage:
#   ./scripts/setup-notes.sh [--clone-private]
#
# Options:
#   --clone-private    Clone private notes repo (requires git SSH access)

# -e: Exit on error
# -u: Exit on undefined variable
# -o pipefail: Exit if any command in pipeline fails

# Configuration
NOTES_DIR="$HOME/generic/notes"
PRIVATE_REPO_URL="${PRIVATE_NOTES_REPO:-git@github.com:RyanSaxe/notes.git}"
CLONE_PRIVATE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --clone-private)
      CLONE_PRIVATE=true
      shift
      ;;
    -h | --help)
      echo "Usage: $0 [--clone-private]"
      echo ""
      echo "Setup Obsidian notes scaffolding for Neovim integration"
      echo ""
      echo "Options:"
      echo "  --clone-private    Clone private notes repo (requires git SSH access)"
      echo "  -h, --help         Show this help message"
      exit 0
      ;;
    *)
      echo "Error: Unknown option: $1" >&2
      echo "Run '$0 --help' for usage" >&2
      exit 1
      ;;
  esac
done

# Check if notes directory already exists
if [[ -d "$NOTES_DIR" ]]; then
  echo "✓ Notes directory already exists: $NOTES_DIR"

  # Check if it's a git repository
  if [[ -d "$NOTES_DIR/.git" ]]; then
    echo "✓ Existing notes directory is a git repository"
    exit 0
  fi

  # If --clone-private is set but directory exists and isn't a repo, error
  if [[ "$CLONE_PRIVATE" == "true" ]]; then
    echo "Error: Notes directory exists but is not a git repository" >&2
    echo "       Cannot clone private repo without removing existing directory" >&2
    echo "       Directory: $NOTES_DIR" >&2
    exit 1
  fi

  # Continue with creating subdirectories if they don't exist
  echo "Creating missing subdirectories..."
else
  # Notes directory doesn't exist
  if [[ "$CLONE_PRIVATE" == "true" ]]; then
    # Clone private repository
    echo "Cloning private notes repository..."
    echo "  Repository: $PRIVATE_REPO_URL"
    echo "  Destination: $NOTES_DIR"

    # Ensure parent directory exists
    mkdir -p "$(dirname "$NOTES_DIR")"

    # Clone the repository
    if git clone "$PRIVATE_REPO_URL" "$NOTES_DIR"; then
      echo "✓ Successfully cloned private notes repository"
      exit 0
    else
      echo "Error: Failed to clone private notes repository" >&2
      echo "       Make sure you have SSH access configured" >&2
      exit 1
    fi
  else
    # Create fresh notes directory structure
    echo "Creating notes directory structure..."
    mkdir -p "$NOTES_DIR"
  fi
fi

# Create subdirectories for Obsidian
# These directories are required by the obsidian.nvim configuration
echo "Creating Obsidian subdirectories..."

# Daily notes folder
if [[ ! -d "$NOTES_DIR/daily" ]]; then
  mkdir -p "$NOTES_DIR/daily"
  echo "  ✓ Created daily/ folder"
else
  echo "  ✓ daily/ folder already exists"
fi

# Templates folder
if [[ ! -d "$NOTES_DIR/templates" ]]; then
  mkdir -p "$NOTES_DIR/templates"
  echo "  ✓ Created templates/ folder"
else
  echo "  ✓ templates/ folder already exists"
fi

# People folder
if [[ ! -d "$NOTES_DIR/people" ]]; then
  mkdir -p "$NOTES_DIR/people"
  echo "  ✓ Created people/ folder"
else
  echo "  ✓ people/ folder already exists"
fi

# Ideas folder
if [[ ! -d "$NOTES_DIR/ideas" ]]; then
  mkdir -p "$NOTES_DIR/ideas"
  echo "  ✓ Created ideas/ folder"
else
  echo "  ✓ ideas/ folder already exists"
fi

# Projects folder
if [[ ! -d "$NOTES_DIR/projects" ]]; then
  mkdir -p "$NOTES_DIR/projects"
  echo "  ✓ Created projects/ folder"
else
  echo "  ✓ projects/ folder already exists"
fi

# Create daily note template if it doesn't exist
DAILY_TEMPLATE="$NOTES_DIR/templates/daily.md"
if [[ ! -f "$DAILY_TEMPLATE" ]]; then
  echo "Creating daily note template..."
  cat > "$DAILY_TEMPLATE" << 'EOF'
# Daily Note

## Tasks

- [ ]

## 06:00 - DESCRIPTION

## Journal

EOF
  echo "  ✓ Created templates/daily.md"
else
  echo "  ✓ templates/daily.md already exists"
fi

# Create person note template if it doesn't exist
PERSON_TEMPLATE="$NOTES_DIR/templates/person.md"
if [[ ! -f "$PERSON_TEMPLATE" ]]; then
  echo "Creating person note template..."
  cat > "$PERSON_TEMPLATE" << 'EOF'
## Tasks

## Summary

## Recent

## Notes

EOF
  echo "  ✓ Created templates/person.md"
else
  echo "  ✓ templates/person.md already exists"
fi

# Create .gitignore if it doesn't exist
GITIGNORE="$NOTES_DIR/.gitignore"
if [[ ! -f "$GITIGNORE" ]]; then
  echo "Creating .gitignore..."
  cat > "$GITIGNORE" << 'EOF'
# Obsidian workspace files
.obsidian/workspace.json
.obsidian/workspace-mobile.json

# macOS
.DS_Store

# Neovim
.nvim.lua
EOF
  echo "  ✓ Created .gitignore"
else
  echo "  ✓ .gitignore already exists"
fi

echo ""
echo "✓ Notes setup complete!"
echo ""
echo "Notes directory: $NOTES_DIR"
echo "Structure:"
echo "  ├── daily/            (daily notes)"
echo "  ├── people/           (people notes)"
echo "  ├── ideas/            (idea notes)"
echo "  ├── projects/         (project notes)"
echo "  ├── templates/        (note templates)"
echo "  │   ├── daily.md      (daily note template)"
echo "  │   └── person.md     (person note template)"
echo "  └── .gitignore        (git ignore rules)"
echo ""
echo "You can now use Obsidian commands in Neovim:"
echo "  <leader>on - Create new note"
echo "  <leader>os - Search notes"
echo "  <leader>ot - Open task picker"
