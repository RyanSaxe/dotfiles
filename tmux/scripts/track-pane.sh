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

# Only update if location changed, stored exists, and stored isn't a format string
# Using case for POSIX-compatible pattern matching (faster than calling external tools)
case "$stored" in
  *'#{'*) exit 0 ;; # Still a format string, skip
  '') exit 0 ;;     # Empty, skip
esac

[ "$curr" = "$stored" ] && exit 0 # No movement, skip

# Set both options in single tmux call
tmux set-option -g @TMUX_PREV_PANE "$stored" \; set-option -g @TMUX_CURR_PANE "$curr"
