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

while :; do
  min=$(date +%M)
  time=$(date +%H:%M)

  # Keep *identical visible width* in both branches: "⟨cap⟩⟨space⟩HH:MM⟨space⟩⟨cap⟩"
  if [[ "$min" == "29" || "$min" == "30" || "$min" == "59" || "$min" == "00" ]]; then
    block="${left_yellow}${mid_yellow} ${time}${right_yellow}"
  else
    block="${left_gray}${mid_gray} ${time}${right_gray}"
  fi

  # Store the fully-renderable string; no nested #{...} left to expand.
  tmux set -gq @time_block "$block"
  # Smooth status redraw only (no content recompute).
  tmux refresh-client -S >/dev/null 2>&1 || true

  # Sleep to the next minute boundary.
  sleep 60
done
