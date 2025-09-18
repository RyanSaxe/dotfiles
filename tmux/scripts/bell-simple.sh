#!/usr/bin/env bash

# Bell indicator with coupled color logic - matches time indicator colors

set -euo pipefail

# Get the directory of this script to find notification-color.sh
script_dir="$(cd "$(dirname "$0")" && pwd)"
color_script="$script_dir/notification-color.sh"

# Get color based on notification and time state
color=$("$color_script")

# Bell icon
bell=" "

# Show bell with dynamically determined color
echo "#[fg=${color}]$bell"

