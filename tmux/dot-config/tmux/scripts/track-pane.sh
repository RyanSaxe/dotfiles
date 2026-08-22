#!/bin/sh
# Track one pane-focus event for "go back" functionality.
# Called by hooks as: track-pane.sh <pane-id>
#
# The hooks run this synchronously and pass the pane that caused the event.
# That matters: a background job that discovers "the current pane" later can
# observe a different selection, and concurrent jobs can overwrite history in
# the middle of one another's read/modify/write cycle.

pane="$1"

[ -n "$pane" ] || exit 0

# Rail panes are display-only, and floating panes are transient popups. Neither
# should become a destination in persistent pane history. The target is passed
# by tmux, so validate it directly instead of rediscovering the active pane.
pane_info() {
  tmux display-message -p -t "$1" \
    '#{pane_id}|#{?#{@rail},rail,content}|#{pane_floating}' 2>/dev/null
}

trackable_pane() {
  info="$(pane_info "$1")" || return 1
  pane_id="${info%%|*}"
  remainder="${info#*|}"
  rail_state="${remainder%%|*}"
  floating="${remainder#*|}"
  [ "$pane_id" = "$1" ] || return 1
  [ "$rail_state" = content ] || return 1
  [ "$floating" != 1 ]
}

trackable_pane "$pane" || exit 0

current="$(tmux show-options -gqv @TMUX_CURR_PANE)"
previous="$(tmux show-options -gqv @TMUX_PREV_PANE)"

# The old implementation stored session:window.pane locations. Treat anything
# that is not a pane ID, or no longer resolves, as stale and re-bootstrap from
# this event. This also cleans values that survived a config reload.
if ! trackable_pane "$current" 2>/dev/null; then
  tmux set-option -g @TMUX_CURR_PANE "$pane" \; \
    set-option -gu @TMUX_PREV_PANE
  exit 0
fi

# A dead/legacy/temporary previous value should never be exposed to Alt-l.
if [ -n "$previous" ] && ! trackable_pane "$previous" 2>/dev/null; then
  tmux set-option -gu @TMUX_PREV_PANE
fi

# No movement: the history is already correct (and any stale previous value
# was cleared above).
[ "$pane" = "$current" ] && exit 0

# Update both values in one tmux command queue so another hook cannot observe
# half-written history.
tmux set-option -g @TMUX_PREV_PANE "$current" \; \
  set-option -g @TMUX_CURR_PANE "$pane"
