#!/usr/bin/env bash

# Count the number of tmux panes with bell notifications across all sessions
# Returns just the count (0 or positive integer)

set -euo pipefail

# Count panes with window_bell_flag=1 across all sessions
# Using window_bell_flag since bell notifications are tracked at window level
count=$(tmux list-panes -a -F '#{window_bell_flag}' 2>/dev/null | grep -c '^1$' || echo "0")

echo "$count"