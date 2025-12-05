#!/usr/bin/env bash
set -euo pipefail

# Background daemon that checks GitHub for comment threads needing attention
# Runs every 15 minutes, sends bell to code-review pane when threads need response
#
# This daemon runs independently of Neovim state - bells will ring even if
# Neovim is already open in the code-review pane.
#
# Uses headless Neovim to reuse existing GraphQL query and classification logic
# from nvim/lua/custom/git/review_threads.lua
#
# Cache file: ~/.cache/github-comments-count
# Bell target: code-review:1 pane

# Check interval in seconds (15 minutes)
CHECK_INTERVAL=900

# Cache files (read by interactive script)
CACHE_FILE="$HOME/.cache/github-comments-count"
TIMESTAMP_FILE="$HOME/.cache/github-comments-timestamp"

# Robust single-instance guard using atomic directory locking
LOCK_DIR="$HOME/.cache/tmux-github-comments-daemon.lock"
PID_FILE="$LOCK_DIR/pid"

# Create cache directory if it doesn't exist
mkdir -p "$(dirname "$LOCK_DIR")" 2> /dev/null || true

# Try to acquire lock atomically using mkdir
if ! mkdir "$LOCK_DIR" 2> /dev/null; then
  # Lock exists - check if the process is still alive
  if [[ -f "$PID_FILE" ]]; then
    existing_pid=$(cat "$PID_FILE" 2> /dev/null || echo "")
    if [[ -n "$existing_pid" ]] && kill -0 "$existing_pid" 2> /dev/null; then
      # Process is alive, exit silently to prevent duplicates
      exit 0
    fi
  fi

  # Lock is stale (process died), remove it and try again
  rm -rf "$LOCK_DIR" 2> /dev/null || true
  if ! mkdir "$LOCK_DIR" 2> /dev/null; then
    # Still couldn't acquire lock (race condition), exit
    exit 0
  fi
fi

# Successfully acquired lock - store our PID
echo "$$" > "$PID_FILE"

# Cleanup function to remove lock
cleanup() {
  rm -rf "$LOCK_DIR" 2> /dev/null || true
}
trap cleanup EXIT INT TERM

# Function to get actionable thread count via headless Neovim
# Returns the count of threads needing response (needs_attention + my_pr)
get_actionable_count() {
  # Run headless Neovim to execute the Lua function
  # The function does a fresh GraphQL fetch and returns the count
  # Timeout after 60 seconds to prevent hanging
  local count
  count=$(timeout 60 nvim --headless \
    -c "lua print(require('custom.git.review_threads').get_actionable_count())" \
    -c "qa" 2>&1 | tail -1)

  # Validate that we got a number
  if [[ "$count" =~ ^[0-9]+$ ]]; then
    echo "$count"
  else
    echo "0"
  fi
}

# Main loop - check GitHub every CHECK_INTERVAL seconds
while :; do
  # Get current actionable count
  count=$(get_actionable_count)

  # Cache the count for the interactive script to display
  echo "$count" > "$CACHE_FILE"

  # Write timestamp so interactive script knows when last check happened
  # Interactive script uses this to trigger bell on each new check
  date +%s > "$TIMESTAMP_FILE"

  # Sleep until next check
  sleep "$CHECK_INTERVAL"
done
