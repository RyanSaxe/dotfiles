#!/bin/sh
# The ONE cross-session jump primitive: land on a pane and let the global
# accent follow the project (sessions are named after projects, so every
# jump syncs `theme mascot` in the background — jumps stay instant).
# Every jumper goes through here: rail jump, go-back-pane. A jump path
# that bypasses this leaves the wrong mascot on screen.
#
#   goto-pane.sh <session> <window-target> <pane-target>

session="$1"
window="$2"
pane="$3"

tmux switch-client -t "$session"
tmux select-window -t "$window"
tmux select-pane -t "$pane"
("$HOME/.local/bin/theme" mascot sync "$session" >/dev/null 2>&1 &)
