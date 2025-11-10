#!/usr/bin/env bash

# Shared color logic for bell and time indicators
# Color priority (highest to lowest):
# 1. Tmux prefix active: green (TokyoNight)
# 2. Notifications: pokemon bright color
# 3. Default: pokemon dim color

set -euo pipefail

# Get the directory of this script to find other scripts
script_dir="$(cd "$(dirname "$0")" && pwd)"
count_script="$script_dir/bell-count.sh"
pokemon_color_script="$script_dir/pokemon-color.sh"

# Check if tmux prefix is currently active
prefix_active=$(tmux display-message -p '#{client_prefix}' 2>/dev/null || echo "0")

# Get notification count
count=$("$count_script")

# Determine color based on conditions (prefix takes precedence)
if [[ "$prefix_active" == "1" ]]; then
  # Prefix active: pokemon prominent color (highest priority)
  "$pokemon_color_script" prominent
elif [[ "$count" -gt 0 ]]; then
  # Notifications: pokemon bright color
  "$pokemon_color_script" bright
else
  # Default: pokemon dim color
  "$pokemon_color_script" dim
fi

