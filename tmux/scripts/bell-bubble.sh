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

if [[ "$count" -gt 0 ]]; then
  echo "#[fg=#{@tokyonight_orange},bg=#{@tokyonight_bg}]#{@left_rounded}#[fg=#{@tokyonight_bg},bg=#{@tokyonight_orange},bold] $count#[fg=#{@tokyonight_orange},bg=#{@tokyonight_bg}]#{@right_rounded}"
else
  echo "#[fg=#{@tokyonight_gray},bg=#{@tokyonight_bg}]#{@left_rounded}#[fg=#{@tokyonight_bg},bg=#{@tokyonight_gray},bold] $count#[fg=#{@tokyonight_gray},bg=#{@tokyonight_bg}]#{@right_rounded}"
fi
