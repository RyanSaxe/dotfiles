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

# Always show bubble - orange for notifications, gray for none
if [[ "$count" -gt 0 ]]; then
    # TokyoNight orange bubble with rounded edges for notifications
    # Format: [left_rounded][orange_bg]   count [right_rounded]
    echo "#[fg=#{@tokyonight_orange},bg=#{@tokyonight_bg}]#{@left_rounded}#[fg=#{@tokyonight_bg},bg=#{@tokyonight_orange},bold]   $count #[fg=#{@tokyonight_orange},bg=#{@tokyonight_bg}]#{@right_rounded}"
else
    # Gray bubble when no notifications (matches other inactive elements)
    # Format: [left_rounded][gray_bg]   0 [right_rounded]
    echo "#[fg=#{@tokyonight_gray},bg=#{@tokyonight_bg}]#{@left_rounded}#[fg=#{@tokyonight_bg},bg=#{@tokyonight_gray},bold]   $count #[fg=#{@tokyonight_gray},bg=#{@tokyonight_bg}]#{@right_rounded}"
fi
