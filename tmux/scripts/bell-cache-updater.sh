#!/usr/bin/env bash
set -euo pipefail

# Background script that monitors bell notifications and caches the count in tmux variable
# This prevents expensive tmux list-panes calls on every status bar render
#
# Monitors:
# - Bell notifications across all tmux panes (window_bell_flag)
#
# Updates tmux variables:
# - @bell_count (number of panes with active bell notifications)

# Robust single-instance guard using atomic directory locking
LOCK_DIR="$HOME/.cache/tmux-bell-cache-updater.lock"
PID_FILE="$LOCK_DIR/pid"

# Create cache directory if it doesn't exist
mkdir -p "$(dirname "$LOCK_DIR")" 2>/dev/null || true

# Try to acquire lock atomically using mkdir
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  # Lock exists - check if the process is still alive
  if [ -f "$PID_FILE" ]; then
    existing_pid=$(cat "$PID_FILE" 2>/dev/null || echo "")
    if [ -n "$existing_pid" ] && kill -0 "$existing_pid" 2>/dev/null; then
      # Process is alive, exit silently to prevent duplicates
      exit 0
    fi
  fi

  # Lock is stale (process died), remove it and try again
  rm -rf "$LOCK_DIR" 2>/dev/null || true
  if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    # Still couldn't acquire lock (race condition), exit
    exit 0
  fi
fi

# Successfully acquired lock - store our PID
echo "$$" > "$PID_FILE"

# Cleanup function to remove lock
cleanup() {
  rm -rf "$LOCK_DIR" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# Function to get current bell count
# Counts panes with window_bell_flag=1 across all sessions
get_bell_count() {
  tmux list-panes -a -F '#{window_bell_flag}' 2>/dev/null | { grep -c '^1$' || true; }
}

# Initialize with current bell count
last_bell_count=$(get_bell_count)
tmux set -gq @bell_count "$last_bell_count"

# Monitor bell status
while :; do
  # Get current bell count
  current_bell_count=$(get_bell_count)

  # Only update and refresh if count changed (avoid unnecessary refreshes)
  if [[ "$current_bell_count" != "$last_bell_count" ]]; then
    tmux set -gq @bell_count "$current_bell_count"
    last_bell_count="$current_bell_count"

    # Trigger a smooth status refresh only when bell count changes
    tmux refresh-client -S >/dev/null 2>&1 || true
  fi

  # Poll every 1 second (balance between responsiveness and CPU usage)
  sleep 1
done
