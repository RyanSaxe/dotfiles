#!/bin/sh
# Track pane focus changes for "go back" functionality
# Called by hooks: after-select-pane, session-window-changed, client-session-changed
#
# OPTIMIZED: Uses single tmux call to get both values, single call to set both
# Reduces from 4 tmux invocations to 1-2 for maximum speed

# Get both values in one tmux call (pipe-separated)
data="$(tmux display-message -p '#{session_name}:#{window_index}.#{pane_index}|#{@TMUX_CURR_PANE}')"
curr="${data%%|*}"
stored="${data#*|}"

# Skip if stored is still an unexpanded format string (tmux bug workaround)
case "$stored" in
  *'#{'*) exit 0 ;;
esac

# No movement - skip update
[ "$curr" = "$stored" ] && exit 0

# Bootstrap case: stored is empty, just initialize CURR_PANE (no previous to track yet)
if [ -z "$stored" ]; then
  tmux set-option -g @TMUX_CURR_PANE "$curr"
  exit 0
fi

# Normal case: store previous and update current in single tmux call
tmux set-option -g @TMUX_PREV_PANE "$stored" \; set-option -g @TMUX_CURR_PANE "$curr"
