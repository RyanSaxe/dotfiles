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

# Capture the client's REAL pane before anything moves. Jump history
# used to rely on the focus hooks replaying movement into
# @TMUX_PREV_PANE, but one logical jump fires up to three hooks
# (switch-client, select-window, select-pane) and each shifts history;
# any focus path the hooks miss leaves @TMUX_CURR_PANE stale besides.
# The jump itself knows the origin, so it records it -- one jump, one
# authoritative write, below.
origin="$(tmux display-message -p '#{pane_id}|#{?#{@rail},rail,content}|#{pane_floating}' 2>/dev/null)"

if ! tmux switch-client -t "$session"; then
  target_failed "goto-pane: session '$session' disappeared"
fi
if ! tmux select-window -t "$window"; then
  target_failed "goto-pane: target window disappeared"
fi
if ! tmux select-pane -t "$pane"; then
  target_failed "goto-pane: target pane disappeared"
fi
# The authoritative history write. The moves above queued hook jobs
# that each rewrite @TMUX_PREV_PANE from their own partial view; routing
# this write through run-shell puts it in the same job queue, AFTER
# them, so the jump's view wins. Rail and floating origins are display
# surfaces, never destinations; same rule as track-pane.sh.
origin_pane="${origin%%|*}"
origin_rest="${origin#*|}"
if [ "${origin_rest%%|*}" = content ] && [ "${origin_rest#*|}" != 1 ] && [ -n "$origin_pane" ] && [ "$origin_pane" != "$pane" ]; then
  tmux run-shell "tmux set-option -g @TMUX_PREV_PANE '$origin_pane' \; set-option -g @TMUX_CURR_PANE '$pane'"
fi

("$HOME/.local/bin/theme" mascot sync "$session" >/dev/null 2>&1 &)
