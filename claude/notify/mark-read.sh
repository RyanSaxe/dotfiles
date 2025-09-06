#!/usr/bin/env bash

# Clear the unread flag for a Claude tmux pane by removing
#   ~/.claude/notify/unread/<pane_id>
# Usage:
#   mark-read.sh [<pane_ref>]
#
# <pane_ref> can be one of:
#   - tmux pane id (e.g., %12)
#   - tmux location (e.g., session:window.pane)
#   - pane tty (e.g., /dev/ttys012)
#   - omitted: if inside tmux, uses current pane; otherwise no-op

set -euo pipefail

utils="$HOME/.claude/claude-utils.sh"
if [[ -f "$utils" ]]; then
  # shellcheck disable=SC1090
  source "$utils"
else
  echo "Error: missing $utils" >&2
  exit 1
fi

pane_ref="${1:-}"

if [[ -z "$pane_ref" && -z "${TMUX:-}" ]]; then
  # No context, nothing to mark
  exit 0
fi

if [[ -z "$pane_ref" ]]; then
  pane_ref="$(tmux display -p '#{pane_id}')"
fi

pane_id="$(resolve_pane_id "$pane_ref")" || exit 0

flag="$HOME/.claude/notify/unread/${pane_id}"
[[ -f "$flag" ]] && rm -f -- "$flag"
echo "Marked read: $pane_id"

