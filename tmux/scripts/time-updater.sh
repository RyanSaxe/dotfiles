#!/usr/bin/env bash
set -euo pipefail

# Resolve theme colors once from tmux; fall back to sane defaults if not set.
tmux_get() { tmux show -gv "$1" 2> /dev/null || echo "$2"; }

# Robust single-instance guard using atomic directory locking (no dependencies)
LOCK_DIR="$HOME/.cache/tmux-time-updater.lock"
PID_FILE="$LOCK_DIR/pid"

# Create cache directory if it doesn't exist
mkdir -p "$(dirname "$LOCK_DIR")" 2> /dev/null || true

# Try to acquire lock atomically using mkdir
if ! mkdir "$LOCK_DIR" 2> /dev/null; then
  # Lock exists - check if the process is still alive
  if [ -f "$PID_FILE" ]; then
    existing_pid=$(cat "$PID_FILE" 2> /dev/null || echo "")
    if [ -n "$existing_pid" ] && kill -0 "$existing_pid" 2> /dev/null; then
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

# Set PID in tmux as well for compatibility
tmux set -gq @time_updater_pid "$$"

# Cleanup function to remove lock and clear tmux PID
cleanup() {
  rm -rf "$LOCK_DIR" 2> /dev/null || true
  tmux set -gq @time_updater_pid ""
}
trap cleanup EXIT INT TERM

# Update time block with minute-based coloring
update_time_block() {
  time=$(date +%H:%M)
  minute=$(date +%M)

  # Get colors (TokyoNight static + Pokemon dynamic)
  bg_color=$(tmux show -gv @tokyonight_bg 2> /dev/null || echo "#1a1b26")
  # Get pokemon colors from cached tmux variables (set by color-cache-updater.sh)
  # This is MUCH faster than calling pokemon-color.sh on every minute
  gray_color=$(tmux show -gv @pokemon_dim 2> /dev/null || echo "#565f89")
  orange_color=$(tmux show -gv @pokemon_bright 2> /dev/null || echo "#ff9e64")
  left_rounded=$(tmux show -gv @left_rounded 2> /dev/null || echo "")
  right_rounded=$(tmux show -gv @right_rounded 2> /dev/null || echo "")

  # Determine color based on minute (orange for 00, 29, 30, 59)
  if [[ "$minute" == "00" || "$minute" == "29" || "$minute" == "30" || "$minute" == "59" ]]; then
    time_color="$orange_color"
  else
    time_color="$gray_color"
  fi

  # Build complete time block with colors
  time_block="#[fg=${time_color},bg=${bg_color}]${left_rounded}#[fg=${bg_color},bg=${time_color},bold] ${time} #[fg=${time_color},bg=${bg_color}]${right_rounded}"

  # Store the complete formatted time block and just the time
  tmux set -gq @current_time "$time"
  tmux set -gq @time_block "$time_block"

  # Smooth status redraw
  tmux refresh-client -S > /dev/null 2>&1 || true
}

# Update immediately on start
update_time_block

# Align to the next minute boundary so updates happen exactly at :00.
now=$(date +%s)
sleep $((60 - now % 60))

while :; do
  update_time_block

  # Sleep to the next minute boundary.
  sleep 60
done
