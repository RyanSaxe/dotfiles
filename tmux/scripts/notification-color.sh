#!/usr/bin/env bash

# Shared color logic for bell and time indicators
# Color priority (highest to lowest):
# 1. Tmux prefix active: green
# 2. Notifications: orange
# 3. Default: blue

set -euo pipefail

# Get the directory of this script to find bell-count.sh
script_dir="$(cd "$(dirname "$0")" && pwd)"
count_script="$script_dir/bell-count.sh"

# Check if tmux prefix is currently active
prefix_active=$(tmux display-message -p '#{client_prefix}' 2>/dev/null || echo "0")

# Get notification count
count=$("$count_script")

# Determine color based on conditions (prefix takes precedence)
if [[ "$prefix_active" == "1" ]]; then
  # Prefix active: green (highest priority)
  echo "#7aa2f7"
elif [[ "$count" -gt 0 ]]; then
  # Notifications: orange
  echo "#ff9e64"
else
  # Default: gray
  echo "#565f89"
fi

