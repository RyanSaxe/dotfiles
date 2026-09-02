#!/usr/bin/env bash
# Superseded by `goto-pane.sh back` — kept only while a live server still runs the old key bindings (PLAN.md Phase 6 deletes it).
# Go back to previous pane (works across sessions)
# Called by: bind -n M-l run-shell '~/.config/tmux/scripts/go-back-pane.sh'

set -euo pipefail

# Previous pane id (%N) from the tmux user option. Pane ids are stable,
# so a target that no longer resolves is really gone — not renumbered.
prev="$(tmux show-options -gqv @TMUX_PREV_PANE)"
[[ -n "$prev" ]] || exit 0

# The old implementation stored session:window.pane locations. Drop those,
# and any pane that was killed or turned into a transient display pane, without
# producing a misleading status message.
case "$prev" in
%*) ;;
*)
  tmux set-option -gu @TMUX_PREV_PANE
  exit 0
  ;;
esac

pane_info="$(tmux display-message -p -t "$prev" \
  '#{pane_id}|#{?#{@rail},rail,content}|#{pane_floating}' 2>/dev/null)"
if [[ -z "$pane_info" ]]; then
  tmux set-option -gu @TMUX_PREV_PANE
  exit 0
fi
pane_id="${pane_info%%|*}"
remainder="${pane_info#*|}"
rail_state="${remainder%%|*}"
floating="${remainder#*|}"
if [[ "$pane_id" != "$prev" || "$rail_state" != content || "$floating" == 1 ]]; then
  tmux set-option -gu @TMUX_PREV_PANE
  exit 0
fi

# goto-pane needs the session name for the mascot sync.
session="$(tmux display-message -p -t "$prev" '#{session_name}' 2>/dev/null)"
[[ -n "$session" ]] || exit 0

# The shared jump primitive switches AND syncs the mascot accent. Call
# the sibling, not a $HOME path: the pair must come from the same tree,
# or a worktree/sandbox copy of one script jumps through the deployed
# copy of the other.
"$(dirname "$(readlink -f "$0")")/goto-pane.sh" "$session" "$prev" "$prev" quiet
