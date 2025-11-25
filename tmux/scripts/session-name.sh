#!/usr/bin/env bash

# Truncate session name to 10 characters with ellipsis if longer

set -euo pipefail

# Get current session name
session_name="$(tmux display-message -p '#S')"

# Truncate if longer than 10 characters
if [[ ${#session_name} -gt 10 ]]; then
  echo "${session_name:0:7}..."
else
  echo "$session_name"
fi
