#!/usr/bin/env bash
set -euo pipefail

# Build the complete formatted session name block with dynamic colors
# This mirrors the pattern used by time-updater.sh for consistency

# Get the directory of this script to find other scripts
script_dir="$(cd "$(dirname "$0")" && pwd)"

# Get the dynamic notification color (prefix/bell/default)
notification_color=$("$script_dir/notification-color.sh")

# Get the session name (truncated if needed)
session_name=$("$script_dir/session-name.sh")

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
