#!/usr/bin/env bash
set -euo pipefail

# Build the complete formatted session name block with dynamic colors
# This mirrors the pattern used by time-updater.sh for consistency

# Get the directory of this script to find other scripts
script_dir="$(cd "$(dirname "$0")" && pwd)"

# Get the session name (truncated if needed)
session_name=$("$script_dir/session-name.sh")

# Calculate notification color based on cached values (much faster than calling scripts)
# Color priority: prefix (prominent) > bells (bright) > default (dim)
prefix_active=$(tmux display-message -p '#{client_prefix}' 2>/dev/null || echo "0")
bell_count=$(tmux show -gv @bell_count 2>/dev/null || echo "0")

# Get pokemon colors from cached tmux variables (set by color-cache-updater.sh)
dim_color=$(tmux show -gv @pokemon_dim 2>/dev/null || echo "#565f89")
prominent_color=$(tmux show -gv @pokemon_prominent 2>/dev/null || echo "#7aa2f7")
bright_color=$(tmux show -gv @pokemon_bright 2>/dev/null || echo "#ff9e64")

# Determine notification color
if [[ "$prefix_active" == "1" ]]; then
  notification_color="$prominent_color"
elif [[ "$bell_count" -gt 0 ]]; then
  notification_color="$bright_color"
else
  notification_color="$dim_color"
fi

# Get static colors and separators from tmux
bg_color=$(tmux show -gv @tokyonight_bg 2>/dev/null || echo "#1a1b26")
left_rounded=$(tmux show -gv @left_rounded 2>/dev/null || echo "")
right_rounded=$(tmux show -gv @right_rounded 2>/dev/null || echo "")

# Build the complete formatted block (same structure as @left_block)
# Format: <rounded left><session name><rounded right>
# Colors: fg=notification_color for separators, bg=notification_color for session name
session_block="#[fg=${notification_color},bg=${bg_color}]${left_rounded}#[fg=${bg_color},bg=${notification_color},bold] ${session_name} #[fg=${notification_color},bg=${bg_color}]${right_rounded} "

# Output the complete block
echo "$session_block"
