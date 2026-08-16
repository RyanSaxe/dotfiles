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

# Validate the whole target before moving anything: after a failed
# switch-client, an unconditional select-window/select-pane would still
# run against the CURRENT session — a dead target must be a no-op, never
# a wrong-session window hop. Emptiness is the pane aliveness test:
# display-message exits 0 for a dead target, printing nothing.
if ! tmux has-session -t "=$session" 2>/dev/null; then
  tmux display-message "goto-pane: session '$session' is gone"
  exit 0
fi
if [ -z "$(tmux display-message -p -t "$pane" '#{pane_id}' 2>/dev/null)" ]; then
  tmux display-message "goto-pane: target pane is gone"
  exit 0
fi

tmux switch-client -t "$session"
tmux select-window -t "$window"
tmux select-pane -t "$pane"
("$HOME/.local/bin/theme" mascot sync "$session" >/dev/null 2>&1 &)
