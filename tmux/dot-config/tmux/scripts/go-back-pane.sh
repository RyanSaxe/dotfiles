#!/usr/bin/env bash
# Go back to previous pane (works across sessions)
# Called by: bind -n M-l run-shell '~/.config/tmux/scripts/go-back-pane.sh'

set -euo pipefail

# Previous pane id (%N) from the tmux user option. Pane ids are stable,
# so a target that no longer resolves is really gone — not renumbered.
prev="$(tmux display-message -p '#{@TMUX_PREV_PANE}')"
[[ -n "$prev" ]] || exit 0

# goto-pane needs the session name for the mascot sync; resolving it
# also proves the pane is still alive. Emptiness is the aliveness test:
# display-message exits 0 for a dead target, printing nothing.
session="$(tmux display-message -p -t "$prev" '#{session_name}' 2>/dev/null)"
if [[ -z "$session" ]]; then
  tmux display-message "go back: previous pane is gone"
  exit 0
fi

# The shared jump primitive switches AND syncs the mascot accent.
"$HOME/.config/tmux/scripts/goto-pane.sh" "$session" "$prev" "$prev"
