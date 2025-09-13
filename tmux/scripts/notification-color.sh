#!/usr/bin/env bash

# Shared color logic for bell and time indicators
# Color priority:
# 1. Default: blue
# 2. Notifications: green
# 3. Special times (00, 29, 30, 59): red
# 4. Notifications + Special time: yellow

set -euo pipefail

# Get the directory of this script to find bell-count.sh
script_dir="$(cd "$(dirname "$0")" && pwd)"
count_script="$script_dir/bell-count.sh"

# Get notification count
count=$("$count_script")

# Get current minute
min=$(date +%M)

# Determine color based on conditions
if [[ "$count" -gt 0 ]] && [[ "$min" == "29" || "$min" == "30" || "$min" == "59" || "$min" == "00" ]]; then
  # Notifications AND special time: yellow
  echo "#e0af68"
elif [[ "$min" == "29" || "$min" == "30" || "$min" == "59" || "$min" == "00" ]]; then
  # Special time only: red
  echo "#f7768e"
elif [[ "$count" -gt 0 ]]; then
  # Notifications only: green
  echo "#9ece6a"
else
  # Default: blue
  echo "#7aa2f7"
fi