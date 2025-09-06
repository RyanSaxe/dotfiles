#!/usr/bin/env bash

# Mark a Claude tmux pane as unread by creating a flag file at
#   ~/.claude/notify/unread/<pane_id>
# Usage:
#   mark-unread.sh [<pane_ref>] [message]
#
# <pane_ref> can be one of:
#   - tmux pane id (e.g., %12)
#   - tmux location (e.g., session:window.pane)
#   - pane tty (e.g., /dev/ttys012)
#   - omitted: if inside tmux, uses current pane; otherwise marks all claude panes unread

set -euo pipefail

utils="$HOME/.claude/claude-utils.sh"
if [[ -f "$utils" ]]; then
  # shellcheck disable=SC1090
  source "$utils"
else
  echo "Error: missing $utils" >&2
  exit 1
fi

mkdir -p "$HOME/.claude/notify/unread"

pane_ref="${1:-}"
message="${2:-}"

write_flag() {
  local pane_id="$1"
  local flag="$HOME/.claude/notify/unread/${pane_id}"
  {
    date +"%Y-%m-%dT%H:%M:%S%z"
    if [[ -n "$message" ]]; then
      echo "$message"
    fi
  } >"$flag"
}

if [[ -z "$pane_ref" && -z "${TMUX:-}" ]]; then
  # Not in tmux and no target provided: mark all Claude panes unread
  while IFS='|' read -r location tty title bell pane_id; do
    write_flag "$pane_id"
  done < <(get_claude_panes)
  exit 0
fi

if [[ -z "$pane_ref" ]]; then
  # Inside tmux: default to current pane
  pane_ref="$(tmux display -p '#{pane_id}')"
fi

pane_id="$(resolve_pane_id "$pane_ref")" || {
  echo "Error: could not resolve pane from '$pane_ref'" >&2
  exit 1
}

write_flag "$pane_id"
echo "Marked unread: $pane_id"

