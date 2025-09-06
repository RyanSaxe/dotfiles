#!/usr/bin/env bash

# Claude Code Notifications Hook
# Reads a JSON payload from stdin (if provided) and marks Claude panes as unread.
# Intended to be used as a "notifications hook" command in Claude Code settings.
#
# Behavior:
# - If CLAUDE_PANE_TTY is set (e.g., /dev/ttys012), mark only that pane as unread.
# - Otherwise, mark all detected Claude panes unread.
# - If jq is available and JSON is piped on stdin, the notification title is recorded in the flag.

set -euo pipefail

msg=""
if [ ! -t 0 ]; then
  # Read stdin (JSON) if piped
  payload=$(cat)
  if command -v jq >/dev/null 2>&1; then
    # Try common fields
    msg=$(echo "$payload" | jq -r '(.title // .message // .event // .type // empty) | tostring' 2>/dev/null || echo "")
    # Guard against null literal
    [[ "$msg" == "null" ]] && msg=""
  fi
fi

notify_dir="$HOME/.claude/notify"
mkdir -p "$notify_dir"

script_dir="$(cd "$(dirname "$0")" && pwd)"
mark_unread="$script_dir/mark-unread.sh"

target="${CLAUDE_PANE_TTY:-}"

if [[ -n "$target" ]]; then
  "$mark_unread" "$target" "$msg"
else
  "$mark_unread" "" "$msg"
fi

