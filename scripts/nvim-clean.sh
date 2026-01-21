#!/usr/bin/env bash
set -Eeuo pipefail

# ──────────────────────────────────────────────────────
# Neovim Cache/State Cleaner
# Interactive cleanup without requiring plugin reinstalls
# ──────────────────────────────────────────────────────

# Colorized output
log() { printf "\033[1;34m::\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m::\033[0m %s\n" "$*"; }
success() { printf "\033[1;32m✓\033[0m %s\n" "$*"; }

# ──────────────────────────────────────────────────────
# Configuration

NVIM_STATE="$HOME/.local/state/nvim"
NVIM_SHARE="$HOME/.local/share/nvim"
NVIM_CACHE="$HOME/.cache/nvim"

# Get the dotfiles directory (for pokemon-colors.lua)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(dirname "$SCRIPT_DIR")"
POKEMON_FILE="$DOTFILES_DIR/nvim/lua/custom/visual/pokemon-colors.lua"

# ──────────────────────────────────────────────────────
# Helper functions

# Get human-readable size
get_size() {
  if [[ -e "$1" ]]; then
    du -sh "$1" 2> /dev/null | cut -f1
  else
    echo "0B"
  fi
}

# Prompt for yes/no, returns 0 for yes, 1 for no
confirm() {
  local prompt="$1"
  local default="${2:-n}"
  local yn

  if [[ "$default" == "y" ]]; then
    read -rp "$prompt [Y/n] " yn
    yn="${yn:-y}"
  else
    read -rp "$prompt [y/N] " yn
    yn="${yn:-n}"
  fi

  [[ "$yn" =~ ^[Yy] ]]
}

# ──────────────────────────────────────────────────────
# Cleaning functions

clean_logs() {
  local size
  size=$(find "$NVIM_STATE" -maxdepth 1 -name "*.log" -exec du -ch {} + 2> /dev/null | tail -1 | cut -f1 || echo "0B")

  log "Log files ($size)"
  echo "    Files: *.log in state directory"

  if confirm "    Delete?"; then
    find "$NVIM_STATE" -maxdepth 1 -name "*.log" -delete 2> /dev/null || true
    rm -f "$NVIM_STATE/log" 2> /dev/null || true
    success "Logs cleared"
  fi
  echo
}

clean_plugin_state() {
  # Clean everything in state EXCEPT these important dirs
  local keep_dirs=("undo" "shada" "sessions")

  local total_size="0B"
  local dirs_to_clean=()

  # Find all directories in state that aren't in the keep list
  if [[ -d "$NVIM_STATE" ]]; then
    for dir in "$NVIM_STATE"/*/; do
      [[ ! -d "$dir" ]] && continue
      local name
      name=$(basename "$dir")

      # Check if it's in the keep list
      local keep=false
      for k in "${keep_dirs[@]}"; do
        if [[ "$name" == "$k" ]]; then
          keep=true
          break
        fi
      done

      if [[ "$keep" == false ]]; then
        dirs_to_clean+=("$dir")
      fi
    done
  fi

  if [[ ${#dirs_to_clean[@]} -eq 0 ]]; then
    log "Plugin state: nothing to clean"
    echo
    return
  fi

  # Calculate total size and list dirs
  total_size=$(du -ch "${dirs_to_clean[@]}" 2> /dev/null | tail -1 | cut -f1 || echo "0B")

  log "Plugin state directories ($total_size)"
  for dir in "${dirs_to_clean[@]}"; do
    local name size
    name=$(basename "$dir")
    size=$(get_size "$dir")
    echo "    - $name ($size)"
  done

  if confirm "    Delete all plugin state?"; then
    for dir in "${dirs_to_clean[@]}"; do
      rm -rf "$dir"
    done
    success "Plugin state cleared"
  fi
  echo
}

clean_cache() {
  if [[ ! -d "$NVIM_CACHE" ]]; then
    log "Cache: directory doesn't exist"
    echo
    return
  fi

  local size
  size=$(get_size "$NVIM_CACHE")

  log "Cache directory ($size)"
  echo "    Path: $NVIM_CACHE"

  if confirm "    Delete?"; then
    rm -rf "$NVIM_CACHE"
    success "Cache cleared"
  fi
  echo
}

clean_undo() {
  if [[ ! -d "$NVIM_STATE/undo" ]]; then
    log "Undo history: directory doesn't exist"
    echo
    return
  fi

  local size count
  size=$(get_size "$NVIM_STATE/undo")
  count=$(find "$NVIM_STATE/undo" -type f 2> /dev/null | wc -l | tr -d ' ')

  log "Undo history ($size, $count files)"
  warn "    Warning: You will lose persistent undo for all files"

  if confirm "    Delete?"; then
    rm -rf "$NVIM_STATE/undo"
    success "Undo history cleared"
  fi
  echo
}

clean_shada() {
  if [[ ! -d "$NVIM_STATE/shada" ]]; then
    log "Shada: directory doesn't exist"
    echo
    return
  fi

  local size
  size=$(get_size "$NVIM_STATE/shada")

  log "Shada ($size)"
  warn "    Warning: You will lose marks, registers, command history"

  if confirm "    Delete?"; then
    rm -rf "$NVIM_STATE/shada"
    success "Shada cleared"
  fi
  echo
}

clean_sessions() {
  if [[ ! -d "$NVIM_STATE/sessions" ]]; then
    log "Sessions: directory doesn't exist"
    echo
    return
  fi

  local size count
  size=$(get_size "$NVIM_STATE/sessions")
  count=$(find "$NVIM_STATE/sessions" -type f 2> /dev/null | wc -l | tr -d ' ')

  log "Saved sessions ($size, $count sessions)"
  warn "    Warning: You will lose all saved session files"

  if confirm "    Delete?"; then
    rm -rf "$NVIM_STATE/sessions"
    success "Sessions cleared"
  fi
  echo
}

clean_pokemon_colors() {
  if [[ ! -f "$POKEMON_FILE" ]]; then
    log "Pokemon colors: file not found at $POKEMON_FILE"
    echo
    return
  fi

  local size count
  size=$(get_size "$POKEMON_FILE")
  # Count pokemon entries (lines starting with '  ["')
  count=$(grep -c '^\s*\["' "$POKEMON_FILE" 2> /dev/null || echo "0")

  log "Pokemon colors ($size, $count pokemon)"
  echo "    Path: $POKEMON_FILE"
  echo "    Will keep 1 pokemon (gengar) as format reference"

  if confirm "    Reset to single pokemon?"; then
    # Keep only gengar entry - extract first pokemon block
    cat > "$POKEMON_FILE" << 'EOF'
return {
  ["gengar"] = {
    _meta = {
      name = "gengar",
      is_shiny = false,
      form = nil,
    },
    colors = {
      "#000000",
      "#8373BD",
      "#6A5A8B",
      "#9C94DE",
      "#414141",
      "#525A6A",
      "#FF7B8B",
      "#FFB4C5",
      "#BD8BC5",
      "#FFFFFF",
      "#BDB4CD",
    },
    dark = {
      prominent = "#8373BD",
      bright = "#FF7B8B",
      dim = "#525A6A",
    },
    light = {
      prominent = "#8373BD",
      bright = "#414141",
      dim = "#525A6A",
    },
  },
}
EOF
    success "Pokemon colors reset (kept gengar)"
  fi
  echo
}

# ──────────────────────────────────────────────────────
# Main

show_help() {
  cat << 'EOF'
Neovim Cache/State Cleaner

Interactive cleanup tool. Prompts for each category.
Plugins and Mason tools are never touched.

USAGE:
    nvim-clean

CATEGORIES:
    Logs           - *.log files (always safe)
    Plugin state   - Regenerable plugin data (safe)
    Cache          - ~/.cache/nvim (safe)
    Undo           - Persistent undo history
    Shada          - Marks, registers, command history
    Sessions       - Saved session files
    Pokemon colors - Reset to single pokemon entry

EOF
}

main() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    show_help
    exit 0
  fi

  echo
  log "Neovim Cleanup"
  echo "    State: $NVIM_STATE"
  echo "    Share: $NVIM_SHARE (plugins - won't touch)"
  echo "    Cache: $NVIM_CACHE"
  echo

  # Safe stuff first
  clean_logs
  clean_plugin_state
  clean_cache

  # Potentially destructive
  clean_undo
  clean_shada
  clean_sessions

  # Pokemon colors
  clean_pokemon_colors

  success "Done!"
}

main "$@"
