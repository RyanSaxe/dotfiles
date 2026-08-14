#!/bin/sh
# Kill a window the instant it's left holding nothing but its rail pane.
#
# Without this, `exit` in the last content pane leaves the display-only
# rail (@rail=1) alone; tmux stretches it across the whole window and the
# daemon's selfHeal reconcile (tuis/rail/src/daemon.ts) only catches it on
# its next tick, so the stretched rail flickers on screen for up to one
# tick. This hook makes the reap instant; selfHeal stays as the backstop
# ("hooks make this instant, this reconcile makes it inevitable").
#
# Called by: set-hook -g pane-exited (tmux.conf), with the dying pane's
# window in $1 (#{window_id}). Falls back to scanning every window if that
# format ever expands empty (observed non-empty on tmux 3.7).
#
# If the window's last pane is the rail, kill-window ends the session too
# when it's the session's only window — same as selfHeal's own reap.

reap_if_rail_only() {
  window="$1"
  panes="$(tmux list-panes -t "$window" -F '#{@rail}' 2>/dev/null)" || return 0
  [ -n "$panes" ] || return 0
  # Any pane without @rail=1 means real content survives; leave it alone.
  echo "$panes" | grep -qv '^1$' && return 0
  tmux kill-window -t "$window" 2>/dev/null
}

window_id="$1"

if [ -n "$window_id" ]; then
  reap_if_rail_only "$window_id"
else
  tmux list-windows -a -F '#{window_id}' 2>/dev/null | while IFS= read -r window; do
    reap_if_rail_only "$window"
  done
fi
