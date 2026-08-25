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
quiet="${4:-}"

notify() {
  case "$quiet" in
  quiet | strict) return 0 ;;
  esac
  tmux display-message "$1"
}

target_failed() {
  notify "$1"
  [ "$quiet" = strict ] && exit 1
  exit 0
}

# Validate the whole target before moving anything: after a failed
# switch-client, an unconditional select-window/select-pane would still
# run against the CURRENT session — a dead target must be a no-op, never
# a wrong-session window hop. Emptiness is the pane aliveness test:
# display-message exits 0 for a dead target, printing nothing.
if ! tmux has-session -t "=$session" 2>/dev/null; then
  target_failed "goto-pane: session '$session' is gone"
fi
if [ -z "$(tmux display-message -p -t "$pane" '#{pane_id}' 2>/dev/null)" ]; then
  target_failed "goto-pane: target pane is gone"
fi

if ! tmux switch-client -t "$session"; then
  target_failed "goto-pane: session '$session' disappeared"
fi
if ! tmux select-window -t "$window"; then
  target_failed "goto-pane: target window disappeared"
fi
if ! tmux select-pane -t "$pane"; then
  target_failed "goto-pane: target pane disappeared"
fi
("$HOME/.local/bin/theme" mascot sync "$session" >/dev/null 2>&1 &)
