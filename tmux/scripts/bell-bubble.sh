#!/usr/bin/env bash

# Create a TokyoNight orange notification bubble for tmux status bar
# Shows the number of panes with bell notifications
# Returns empty string if no notifications

set -euo pipefail

# Get the directory of this script to find bell-count.sh
script_dir="$(cd "$(dirname "$0")" && pwd)"
count_script="$script_dir/bell-count.sh"

# Get notification count
count=$("$count_script")

# Only show bubble if there are notifications
if [[ "$count" -gt 0 ]]; then
    # TokyoNight orange bubble with rounded edges
    # Format: [left_rounded][orange_bg] 🔔 count [right_rounded]
    echo "#[fg=#{@tokyonight_orange},bg=#{@tokyonight_bg}]#{@left_rounded}#[fg=#{@tokyonight_bg},bg=#{@tokyonight_orange},bold] 🔔 $count #[fg=#{@tokyonight_orange},bg=#{@tokyonight_bg}]#{@right_rounded}"
else
    # No notifications - return empty string
    echo ""
fi