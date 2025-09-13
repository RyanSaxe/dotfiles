#!/usr/bin/env bash

# Simple bell indicator - shows a bell icon in orange when notifications exist, gray otherwise

set -euo pipefail

# Get the directory of this script to find bell-count.sh
script_dir="$(cd "$(dirname "$0")" && pwd)"
count_script="$script_dir/bell-count.sh"

# Get notification count
count=$("$count_script")

# Bell icon
bell=" "

if [[ "$count" -gt 0 ]]; then
  # Show orange bell when notifications exist
  echo "#[fg=#ff9e64]$bell"
else
  # Show gray bell when no notifications
  echo "#[fg=#565f89]$bell"
fi

