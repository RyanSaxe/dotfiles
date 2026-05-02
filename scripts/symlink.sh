#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

# ──────────────────────────────────────────────────────
# Dotfiles Symlink Manager
# Creates symlinks for all dotfiles with version control management
# ──────────────────────────────────────────────────────

# Colorized logging (matching install.sh style)
log() { printf "\033[1;34m[INFO]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[WARN]\033[0m %s\n" "$*"; }
err() { printf "\033[1;31m[ERR ]\033[0m %s\n" "$*" >&2; }
success() { printf "\033[1;32m[OK  ]\033[0m %s\n" "$*"; }

# ──────────────────────────────────────────────────────
# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(dirname "$SCRIPT_DIR")"

# Platform-specific paths
# macOS uses ~/Library/Application Support for lazygit, Linux uses ~/.config
if [[ "$OSTYPE" == "darwin"* ]]; then
  export LAZYGIT_CONFIG_DIR="$HOME/Library/Application Support/lazygit"
else
  export LAZYGIT_CONFIG_DIR="$HOME/.config/lazygit"
fi

# Load dotfile mappings from config file
DOTFILE_MAPPINGS=()
while IFS= read -r line || [[ -n "$line" ]]; do
  [[ -n "$line" ]] && DOTFILE_MAPPINGS[${#DOTFILE_MAPPINGS[@]}]="$line"
done < "$DOTFILES_DIR/config/symlinks.txt"

REQUESTED_PATHS=()

# ──────────────────────────────────────────────────────
# Helper functions

is_stateful_runtime_dir() {
  case "$1" in
    "$HOME/.claude") return 0 ;;
    *) return 1 ;;
  esac
}

preserve_runtime_state() {
  local source=$1
  local target=$2

  if cp -R -n "$target"/. "$source"/ 2> /dev/null; then
    success "✓ Preserved existing runtime state in $source"
  else
    warn "Could not preserve runtime state from $target before symlinking"
  fi
}

resolve_existing_path() {
  local path=$1
  local dir
  local base

  dir="$(dirname "$path")"
  base="$(basename "$path")"

  if [[ -d "$path" ]]; then
    (cd -P "$path" && pwd)
  elif [[ -e "$path" || -L "$path" ]]; then
    (cd -P "$dir" && printf '%s/%s\n' "$(pwd)" "$base")
  else
    return 1
  fi
}

is_symlink_to_path() {
  local link_path=$1
  local expected_target=$2

  [[ -L "$link_path" ]] || return 1

  local resolved_link
  local resolved_expected
  resolved_link="$(resolve_existing_path "$link_path")" || return 1
  resolved_expected="$(resolve_existing_path "$expected_target")" || return 1

  [[ "$resolved_link" == "$resolved_expected" ]]
}

materialize_runtime_dir_if_needed() {
  local source=$1
  local target=$2

  is_stateful_runtime_dir "$target" || return 0
  is_symlink_to_path "$target" "$source" || return 0

  local tmp_target="${target}.materializing.$$"

  log "Materializing runtime directory: $target"
  mkdir -p "$tmp_target"

  if ! cp -R -p "$source"/. "$tmp_target"/; then
    rm -rf "$tmp_target"
    err "Could not copy runtime state from $source to $tmp_target"
    return 1
  fi

  rm -f "$target"
  mv "$tmp_target" "$target"
  success "✓ Replaced broad symlink with real runtime directory at $target"
}

prepare_runtime_parent_dirs() {
  materialize_runtime_dir_if_needed "$DOTFILES_DIR/claude" "$HOME/.claude"
}

create_symlink() {
  local source=$1
  local target=$2

  # Create target directory if it doesn't exist
  mkdir -p "$(dirname "$target")"

  # Handle existing files/symlinks safely
  if [[ -e "$target" || -L "$target" ]]; then
    if [[ -L "$target" ]]; then
      # It's a symlink, safe to remove
      rm -f "$target"
    else
      if [[ -d "$source" && -d "$target" ]] && is_stateful_runtime_dir "$target"; then
        preserve_runtime_state "$source" "$target"
      fi

      # It's a real file/directory, back it up
      local timestamp=$(date +%Y%m%d_%H%M%S)
      local backup_name="$(basename "$target")_${timestamp}"
      local backup_path="$DOTFILES_DIR/backups/$backup_name"
      mv "$target" "$backup_path"

      # Create restore instructions
      echo "$backup_path → $target" >> "$DOTFILES_DIR/backups/RESTORE_INSTRUCTIONS.txt"
      warn "Backed up existing file to $backup_path"
    fi
  fi

  # Create the symlink (use -n for BSD/macOS compatibility)
  if ln -sfn "$source" "$target"; then
    success "✓ $target → $source"
    return 0
  else
    err "✗ Failed to create symlink: $target → $source"
    return 1
  fi
}

# ──────────────────────────────────────────────────────
# Main symlink function

symlink_dotfiles() {
  local failed=0

  log "Starting dotfiles symlinking..."
  log "Dotfiles directory: $DOTFILES_DIR"
  echo

  # Verify dotfiles directory exists
  if [[ ! -d "$DOTFILES_DIR" ]]; then
    err "Dotfiles directory not found: $DOTFILES_DIR"
    exit 1
  fi

  prepare_runtime_parent_dirs

  # Process each dotfile mapping
  for mapping in "${DOTFILE_MAPPINGS[@]}"; do
    IFS=: read -r src_path target_path <<< "$mapping"
    local source="$DOTFILES_DIR/$src_path"
    local target=$(eval echo "$target_path")

    if ! should_process_mapping "$src_path"; then
      continue
    fi

    if [[ ! -e "$source" ]]; then
      warn "Source not found, skipping: $source"
      continue
    fi

    if ! create_symlink "$source" "$target"; then
      ((failed++))
    fi
  done

  echo
  if ((failed == 0)); then
    success "✅ All dotfiles symlinked successfully!"
  else
    err "❌ $failed symlinks failed"
    exit 1
  fi
}

# ──────────────────────────────────────────────────────
# Command line options

show_help() {
  cat << EOF
Dotfiles Symlink Manager

USAGE:
    $(basename "$0") [OPTIONS]

OPTIONS:
    -h, --help      Show this help message
    -l, --list      List all configured symlinks
    -d, --dry-run   Show what would be done without making changes
    -o, --only PATH Only process a specific source path from config/symlinks.txt
                    Repeatable; e.g. --only nvim --only zsh/.zshrc

EXAMPLES:
    $(basename "$0")                 # Create all symlinks
    $(basename "$0") --list          # Show configured mappings
    $(basename "$0") --dry-run       # Preview changes
    $(basename "$0") --only nvim --only zsh/.zshrc

EOF
}

should_process_mapping() {
  local src_path=$1

  if [[ ${#REQUESTED_PATHS[@]} -eq 0 ]]; then
    return 0
  fi

  local requested
  for requested in "${REQUESTED_PATHS[@]}"; do
    if [[ "$src_path" == "$requested" ]]; then
      return 0
    fi
  done

  return 1
}

list_mappings() {
  log "Configured dotfile mappings:"
  echo
  local total_lines expected_mappings
  total_lines=$(wc -l < "$DOTFILES_DIR/config/symlinks.txt" 2> /dev/null || echo 0)
  expected_mappings=${#DOTFILE_MAPPINGS[@]}

  if [[ $expected_mappings -ne $total_lines ]]; then
    warn "⚠ Found $expected_mappings mappings but $total_lines lines in config - possible missing newline issue"
  fi

  for mapping in "${DOTFILE_MAPPINGS[@]}"; do
    IFS=: read -r src_path target_path <<< "$mapping"
    local source="$DOTFILES_DIR/$src_path"
    local target=$(eval echo "$target_path")

    if ! should_process_mapping "$src_path"; then
      continue
    fi

    printf "  %-30s → %s\n" "$source" "$target"
  done
}

dry_run() {
  log "DRY RUN - showing what would be done:"
  echo

  if is_symlink_to_path "$HOME/.claude" "$DOTFILES_DIR/claude"; then
    warn "MATERIALIZE: $HOME/.claude is a broad symlink; it would be replaced with a real runtime directory copied from $DOTFILES_DIR/claude"
  fi

  for mapping in "${DOTFILE_MAPPINGS[@]}"; do
    IFS=: read -r src_path target_path <<< "$mapping"
    local source="$DOTFILES_DIR/$src_path"
    local target=$(eval echo "$target_path")

    if ! should_process_mapping "$src_path"; then
      continue
    fi

    if [[ ! -e "$source" ]]; then
      warn "SKIP: Source not found - $source"
      continue
    fi

    if [[ -e "$target" || -L "$target" ]]; then
      if [[ -L "$target" ]]; then
        warn "REMOVE: Existing symlink at $target"
      else
        warn "BACKUP: Existing file at $target"
      fi
    fi

    log "LINK: $target → $source"
  done
}

# ──────────────────────────────────────────────────────
# Main execution

main() {
  local dry_run_mode=false

  while [[ $# -gt 0 ]]; do
    case $1 in
      -h | --help)
        show_help
        exit 0
        ;;
      -l | --list)
        list_mappings
        exit 0
        ;;
      -d | --dry-run)
        dry_run_mode=true
        shift
        ;;
      -o | --only)
        if [[ $# -lt 2 ]]; then
          err "Missing value for $1"
          exit 1
        fi
        REQUESTED_PATHS[${#REQUESTED_PATHS[@]}]="$2"
        shift 2
        ;;
      *)
        err "Unknown option: $1"
        show_help
        exit 1
        ;;
    esac
  done

  if [[ "$dry_run_mode" == true ]]; then
    dry_run
  else
    symlink_dotfiles
  fi
}

# Only run main if script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
