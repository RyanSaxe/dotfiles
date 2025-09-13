#!/usr/bin/env bash
set -euo pipefail

# Resolve theme colors once from tmux; fall back to sane defaults if not set.
tmux_get() { tmux show -gv "$1" 2>/dev/null || echo "$2"; }

# PID guard: kill existing process and start fresh
PID_OPT='@time_updater_pid'
if existing_pid=$(tmux show -gv "$PID_OPT" 2>/dev/null); then
  if [ -n "$existing_pid" ] && kill -0 "$existing_pid" 2>/dev/null; then
    # Kill the existing process to restart with updated logic
    kill "$existing_pid" 2>/dev/null || true
    sleep 0.1 # Brief pause to ensure cleanup
  fi
fi
tmux set -gq "$PID_OPT" "$$"
cleanup() {
  tmux set -gq "$PID_OPT" ""
}
trap cleanup EXIT INT TERM

# Update time block with minute-based coloring
update_time_block() {
  time=$(date +%H:%M)
  minute=$(date +%M)

  # Get TokyoNight colors
  bg_color=$(tmux show -gv @tokyonight_bg 2>/dev/null || echo "#1a1b26")
  gray_color=$(tmux show -gv @tokyonight_gray 2>/dev/null || echo "#565f89")
  orange_color=$(tmux show -gv @tokyonight_orange 2>/dev/null || echo "#ff9e64")
  left_rounded=$(tmux show -gv @left_rounded 2>/dev/null || echo "")
  right_rounded=$(tmux show -gv @right_rounded 2>/dev/null || echo "")

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
  tmux refresh-client -S >/dev/null 2>&1 || true
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
