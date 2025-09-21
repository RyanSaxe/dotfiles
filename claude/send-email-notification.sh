#!/usr/bin/env bash

# Notification script for Claude Code using ntfy.sh
# Sends push notifications when Claude needs attention
# Reads JSON from stdin when available to get specific context

# Load environment variables from .env file if it exists
# Get the actual source location (handles symlinks)
if [[ -L "${BASH_SOURCE[0]}" ]]; then
  # It's a symlink, resolve it
  SCRIPT_PATH="$(readlink "${BASH_SOURCE[0]}")"
  # If readlink gives relative path, make it absolute
  if [[ "$SCRIPT_PATH" != /* ]]; then
    SCRIPT_PATH="$(dirname "${BASH_SOURCE[0]}")/$SCRIPT_PATH"
  fi
else
  SCRIPT_PATH="${BASH_SOURCE[0]}"
fi
DOTFILES_DIR="$(cd "$(dirname "$SCRIPT_PATH")/.." && pwd)"

if [[ -f "$DOTFILES_DIR/.env" ]]; then
  source "$DOTFILES_DIR/.env"
fi

# Check for notification ID
if [[ -z "$CLAUDE_NOTIFICATION_ID" ]]; then
  echo "Error: CLAUDE_NOTIFICATION_ID not set. Please set it in $DOTFILES_DIR/.env" >&2
  echo "Example: CLAUDE_NOTIFICATION_ID=\"my-random-string-12345\"" >&2
  exit 1
fi

# Build the ntfy channel URL
NTFY_CHANNEL="claude-code-notification-${CLAUDE_NOTIFICATION_ID}"
NTFY_URL="https://ntfy.sh/${NTFY_CHANNEL}"

# Default message
MESSAGE="Claude Code needs your attention"
TITLE="Claude Code"

# Check if we have an argument first
if [[ -n "$1" ]]; then
  MESSAGE="$1"
# Try to read JSON from stdin if available (Claude passes hook data as JSON)
elif [ ! -t 0 ]; then
  # Read JSON from stdin and try to extract relevant info
  json_input=$(cat)

  # Try to extract type and reason from JSON using basic parsing
  # Claude typically sends: {"type":"notification","reason":"...","title":"..."}
  if command -v jq >/dev/null 2>&1; then
    # If jq is available, use it for proper JSON parsing
    reason=$(echo "$json_input" | jq -r '.reason // empty' 2>/dev/null)
    title=$(echo "$json_input" | jq -r '.title // empty' 2>/dev/null)
    type=$(echo "$json_input" | jq -r '.type // empty' 2>/dev/null)

    if [[ -n "$reason" ]]; then
      MESSAGE="$reason"
    elif [[ -n "$title" ]]; then
      MESSAGE="$title"
    fi

    if [[ -n "$type" ]]; then
      TITLE="Claude: $type"
    fi
  else
    # Fallback: basic grep parsing if jq not available
    reason=$(echo "$json_input" | grep -o '"reason":"[^"]*"' | cut -d'"' -f4)
    title=$(echo "$json_input" | grep -o '"title":"[^"]*"' | cut -d'"' -f4)

    if [[ -n "$reason" ]]; then
      MESSAGE="$reason"
    elif [[ -n "$title" ]]; then
      MESSAGE="$title"
    fi
  fi
fi

# Send notification via ntfy.sh
if command -v curl >/dev/null 2>&1; then
  curl -s \
    -H "Title: ${TITLE}" \
    -H "Priority: default" \
    -H "Tags: robot" \
    -d "${MESSAGE}" \
    "${NTFY_URL}" >/dev/null 2>&1

  if [[ $? -eq 0 ]]; then
    echo "Notification sent via ntfy: ${MESSAGE}"
  else
    echo "Failed to send ntfy notification" >&2
  fi
else
  echo "Error: curl not found, cannot send ntfy notification" >&2
fi

# Always play terminal bell as backup
printf '\a'