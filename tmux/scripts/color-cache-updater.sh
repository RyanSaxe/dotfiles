#!/usr/bin/env bash
set -euo pipefail

# Background script that monitors pokemon color files and caches results in tmux variables
# This prevents expensive shell script calls on every status bar render
#
# Monitors:
# - ~/.cache/pokemon-colors.env (pokemon colors from nvim dashboard)
# - ~/.config/tmux/pokemon-colors.conf (manual overrides)
#
# Updates tmux variables:
# - @pokemon_dim
# - @pokemon_prominent
# - @pokemon_bright

# Get the directory of this script to find pokemon-color.sh
script_dir="$(cd "$(dirname "$0")" && pwd)"
pokemon_color_script="$script_dir/pokemon-color.sh"

# Files to monitor
cache_file="$HOME/.cache/pokemon-colors.env"
config_file="$HOME/.config/tmux/pokemon-colors.conf"

# Robust single-instance guard using atomic directory locking
LOCK_DIR="$HOME/.cache/tmux-color-cache-updater.lock"
PID_FILE="$LOCK_DIR/pid"

# Create cache directory if it doesn't exist
mkdir -p "$(dirname "$LOCK_DIR")" 2> /dev/null || true

# Try to acquire lock atomically using mkdir
if ! mkdir "$LOCK_DIR" 2> /dev/null; then
  # Lock exists - check if the process is still alive
  if [ -f "$PID_FILE" ]; then
    existing_pid=$(cat "$PID_FILE" 2> /dev/null || echo "")
    if [ -n "$existing_pid" ] && kill -0 "$existing_pid" 2> /dev/null; then
      # Process is alive, exit silently to prevent duplicates
      exit 0
    fi
  fi

  # Lock is stale (process died), remove it and try again
  rm -rf "$LOCK_DIR" 2> /dev/null || true
  if ! mkdir "$LOCK_DIR" 2> /dev/null; then
    # Still couldn't acquire lock (race condition), exit
    exit 0
  fi
fi

# Successfully acquired lock - store our PID
echo "$$" > "$PID_FILE"

# Cleanup function to remove lock
cleanup() {
  rm -rf "$LOCK_DIR" 2> /dev/null || true
}
trap cleanup EXIT INT TERM

# Function to get file modification time (returns empty if file doesn't exist)
get_mtime() {
  local file="$1"
  if [[ -f "$file" ]]; then
    # Use stat command (cross-platform: macOS uses -f, Linux uses -c)
    if stat -f "%m" "$file" 2> /dev/null; then
      return
    elif stat -c "%Y" "$file" 2> /dev/null; then
      return
    fi
  fi
  echo "0"
}

# Function to blend two hex colors at a given weight
# Usage: blend_colors "#ff9e64" "#1a1b26" 50
# Returns: blended color (50% first color, 50% second color)
blend_colors() {
  local color1="$1" # First color (e.g., pokemon bright)
  local color2="$2" # Second color (e.g., background)
  local weight="$3" # Weight of first color (0-100)

  # Remove # prefix and convert to uppercase
  color1="${color1#\#}"
  color2="${color2#\#}"

  # Parse RGB components (hex to decimal)
  local r1=$((16#${color1:0:2}))
  local g1=$((16#${color1:2:2}))
  local b1=$((16#${color1:4:2}))

  local r2=$((16#${color2:0:2}))
  local g2=$((16#${color2:2:2}))
  local b2=$((16#${color2:4:2}))

  # Blend colors: new = (color1 * weight + color2 * (100-weight)) / 100
  local r=$(((r1 * weight + r2 * (100 - weight)) / 100))
  local g=$(((g1 * weight + g2 * (100 - weight)) / 100))
  local b=$(((b1 * weight + b2 * (100 - weight)) / 100))

  # Convert back to hex and format
  printf "#%02x%02x%02x" "$r" "$g" "$b"
}

# Function to update cached colors in tmux variables
update_color_cache() {
  # Call pokemon-color.sh once for each color type and cache in tmux variables
  local dim_color prominent_color bright_color

  dim_color=$("$pokemon_color_script" dim 2> /dev/null || echo "#565f89")
  prominent_color=$("$pokemon_color_script" prominent 2> /dev/null || echo "#7aa2f7")
  bright_color=$("$pokemon_color_script" bright 2> /dev/null || echo "#ff9e64")

  # Store in tmux variables (these are fast to read)
  tmux set -gq @pokemon_dim "$dim_color"
  tmux set -gq @pokemon_prominent "$prominent_color"
  tmux set -gq @pokemon_bright "$bright_color"

  # Update JankyBorders colors (do this BEFORE tmux refresh)
  # If borders is running, this updates the existing process with the new color
  # If not running, this starts borders with the new color (only active_color, no other settings)
  local borders_color="0xff${prominent_color#\#}"
  borders active_color="$borders_color" > /dev/null 2>&1 || true

  # Update sketchybar colors (trigger custom event if sketchybar is running)
  # This causes all items subscribed to pokemon_colors_changed to refresh
  if pgrep -q sketchybar; then
    sketchybar --trigger pokemon_colors_changed > /dev/null 2>&1 || true
  fi

  # Trigger a smooth status refresh (after all color updates are complete)
  tmux refresh-client -S > /dev/null 2>&1 || true
}

# Initialize cache on startup
update_color_cache

# Track last modification times
last_cache_mtime=$(get_mtime "$cache_file")
last_config_mtime=$(get_mtime "$config_file")

# Monitor files for changes
while :; do
  # Check if files have been modified
  current_cache_mtime=$(get_mtime "$cache_file")
  current_config_mtime=$(get_mtime "$config_file")

  # Update cache if either file changed
  if [[ "$current_cache_mtime" != "$last_cache_mtime" ]] \
    || [[ "$current_config_mtime" != "$last_config_mtime" ]]; then
    update_color_cache
    last_cache_mtime="$current_cache_mtime"
    last_config_mtime="$current_config_mtime"
  fi

  # Poll every 2 seconds (lightweight file stat operation)
  sleep 2
done
