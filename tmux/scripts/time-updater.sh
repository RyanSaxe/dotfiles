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

# Update time only - colors are handled by tmux format expansion
update_time_block() {
  time=$(date +%H:%M)

  # Store just the time - tmux.conf will handle color formatting
  tmux set -gq @current_time "$time"
  # Smooth status redraw only (no content recompute).
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
