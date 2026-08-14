#!/usr/bin/env bash
# Go back to previous pane (works across sessions)
# Called by: bind -n M-l run-shell '~/.config/tmux/scripts/go-back-pane.sh'

set -euo pipefail

# Get the previous pane location from tmux user option
prev="$(tmux display-message -p '#{@TMUX_PREV_PANE}')"

if [[ -n "$prev" ]]; then
  # Extract session (before :), window (between : and .), pane (after .)
  session="${prev%%:*}"
  window_pane="${prev#*:}"
  window="${window_pane%.*}"
  pane="${window_pane#*.}"

  # The shared jump primitive switches AND syncs the pokemon accent.
  "$HOME/.config/tmux/scripts/goto-pane.sh" "$session" ":$window" ".$pane"
fi
