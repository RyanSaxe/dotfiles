#!/usr/bin/env bash
set -euo pipefail

# Resolve theme colors once from tmux; fall back to sane defaults if not set.
tmux_get() { tmux show -gv "$1" 2>/dev/null || echo "$2"; }
BG=$(tmux_get @tokyonight_bg "#1a1b26")
FG=$(tmux_get @tokyonight_fg "#c0caf5")
GRAY=$(tmux_get @tokyonight_gray "#565f89")
YELLOW=$(tmux_get @tokyonight_yellow "#e0af68")
CYAN=$(tmux_get @tokyonight_cyan "#7dcfff")

# Rounded glyphs (require Nerd Font)
LEFT_ROUNDED=$(tmux_get @left_rounded "")
RIGHT_ROUNDED=$(tmux_get @right_rounded "")

# Build color segments using *literal* hex so tmux can render them directly.
left_gray="#[fg=${GRAY},bg=${BG}]${LEFT_ROUNDED}"
left_yellow="#[fg=${YELLOW},bg=${BG}]${LEFT_ROUNDED}"
mid_gray='#[fg='"${BG}"',bg='"${GRAY}"',bold]'
mid_yellow='#[fg='"${BG}"',bg='"${YELLOW}"',bold]'
right_gray=" #[fg=${GRAY},bg=${BG}]${RIGHT_ROUNDED}"
right_yellow=" #[fg=${YELLOW},bg=${BG}]${RIGHT_ROUNDED}"

# PID guard: store & check a PID so we don't spawn multiple loops.
PID_OPT='@time_updater_pid'
if existing_pid=$(tmux show -gv "$PID_OPT" 2>/dev/null); then
  if [ -n "$existing_pid" ] && kill -0 "$existing_pid" 2>/dev/null; then
    exit 0
  fi
fi
tmux set -gq "$PID_OPT" "$$"
cleanup() {
  tmux set -gq "$PID_OPT" ""
}
trap cleanup EXIT INT TERM

# Align to the next minute boundary so updates happen exactly at :00.
now=$(date +%s)
sleep $((60 - now % 60))

# No bell flashing - removed bell flash refresh loop

while :; do
  min=$(date +%M)
  time=$(date +%H:%M)

  # Get current notification color using the shared color logic
  script_dir="$(cd "$(dirname "$0")" && pwd)"
  color=$("$script_dir/notification-color.sh")

  # Get rounded separators from tmux
  left_rounded=$(tmux show -gv @left_rounded 2>/dev/null || echo "")
  right_rounded=$(tmux show -gv @right_rounded 2>/dev/null || echo "")
  bg_color=$(tmux show -gv @tokyonight_bg 2>/dev/null || echo "#1a1b26")

  # Create time block with same styling as session name (background color + rounded separators)
  block="#[fg=${color},bg=${bg_color}]${left_rounded}#[fg=${bg_color},bg=${color},bold] ${time} #[fg=${color},bg=${bg_color}]${right_rounded} "

  # Store the fully-renderable string; no nested #{...} left to expand.
  tmux set -gq @time_block "$block"
  # Smooth status redraw only (no content recompute).
  tmux refresh-client -S >/dev/null 2>&1 || true

  # Sleep to the next minute boundary.
  sleep 60
done
