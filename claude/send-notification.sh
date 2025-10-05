#!/usr/bin/env bash

# Improved notification script for Claude Code using ntfy.sh
# Properly parses the JSON payload from Claude Code hooks

# Check for notification ID
if [[ -z "$CLAUDE_NOTIFICATION_ID" ]]; then
  echo "Error: CLAUDE_NOTIFICATION_ID not set. Please set it in ~/.zshrc or .env" >&2
  echo "Example: CLAUDE_NOTIFICATION_ID=\"my-random-string-12345\"" >&2
  exit 1
fi

# Build the ntfy channel URL
NTFY_CHANNEL="claude-code-notification-${CLAUDE_NOTIFICATION_ID}"
NTFY_URL="https://ntfy.sh/${NTFY_CHANNEL}"

# Default values
MESSAGE="Claude Code needs your attention"
TITLE="Claude Code"
PRIORITY="default"
TAGS="robot"

# Parse JSON input from stdin if available
if [ ! -t 0 ]; then
  json_input=$(cat)

  # Parse the JSON using jq if available
  if command -v jq >/dev/null 2>&1; then
    # Extract fields that Claude Code actually provides
    hook_event=$(echo "$json_input" | jq -r '.hook_event_name // empty' 2>/dev/null)
    message_field=$(echo "$json_input" | jq -r '.message // empty' 2>/dev/null)
    session_id=$(echo "$json_input" | jq -r '.session_id // empty' 2>/dev/null)
    cwd=$(echo "$json_input" | jq -r '.cwd // empty' 2>/dev/null)

    # Customize message based on hook event type
    case "$hook_event" in
      "Notification")
        TITLE="Claude Code: Needs Attention"
        if [[ -n "$message_field" ]]; then
          MESSAGE="$message_field"
        else
          # Check if it's a permission request or idle notification
          if [[ "$json_input" == *"permission"* ]]; then
            MESSAGE="Claude needs permission to use a tool"
          else
            MESSAGE="Claude has been idle for 60+ seconds"
          fi
        fi
        PRIORITY="high"
        TAGS="warning,robot"
        ;;

      "Stop")
        TITLE="Claude Code: Task Complete"
        MESSAGE="Claude has finished responding"
        PRIORITY="default"
        TAGS="white_check_mark,robot"
        ;;

      "UserPromptSubmit")
        # Usually we don't want notifications for this
        TITLE="Claude Code: New Prompt"
        MESSAGE="User submitted a new prompt"
        PRIORITY="low"
        TAGS="speech_balloon,robot"
        ;;

      "PreToolUse")
        # Extract tool name if available
        tool_name=$(echo "$json_input" | jq -r '.tool_name // empty' 2>/dev/null)
        if [[ -n "$tool_name" ]]; then
          TITLE="Claude Code: Using Tool"
          MESSAGE="Using tool: $tool_name"
        else
          TITLE="Claude Code: Tool Use"
          MESSAGE="Claude is using a tool"
        fi
        PRIORITY="low"
        TAGS="wrench,robot"
        ;;

      "PostToolUse")
        # Extract tool name if available
        tool_name=$(echo "$json_input" | jq -r '.tool_name // empty' 2>/dev/null)
        if [[ -n "$tool_name" ]]; then
          TITLE="Claude Code: Tool Complete"
          MESSAGE="Completed tool: $tool_name"
        else
          TITLE="Claude Code: Tool Complete"
          MESSAGE="Tool execution completed"
        fi
        PRIORITY="low"
        TAGS="check,robot"
        ;;

      *)
        # Unknown hook event
        if [[ -n "$hook_event" ]]; then
          TITLE="Claude Code: $hook_event"
        fi
        if [[ -n "$message_field" ]]; then
          MESSAGE="$message_field"
        fi
        ;;
    esac

    # Add working directory to message if available and different from home
    if [[ -n "$cwd" ]] && [[ "$cwd" != "$HOME" ]]; then
      project_name=$(basename "$cwd")
      MESSAGE="[$project_name] $MESSAGE"
    fi

  else
    # Fallback without jq - just try to extract the message field
    message_field=$(echo "$json_input" | grep -o '"message":"[^"]*"' | cut -d'"' -f4)
    hook_event=$(echo "$json_input" | grep -o '"hook_event_name":"[^"]*"' | cut -d'"' -f4)

    if [[ -n "$message_field" ]]; then
      MESSAGE="$message_field"
    fi

    if [[ "$hook_event" == "Notification" ]]; then
      TITLE="Claude Code: Needs Attention"
      PRIORITY="high"
      TAGS="warning,robot"
    elif [[ "$hook_event" == "Stop" ]]; then
      TITLE="Claude Code: Complete"
      PRIORITY="default"
      TAGS="white_check_mark,robot"
    fi
  fi
elif [[ -n "$1" ]]; then
  # Command line argument provided
  MESSAGE="$1"
fi

# Send notification via ntfy.sh
if command -v curl >/dev/null 2>&1; then
  # Send the notification with all the customized fields
  response=$(curl -s \
    -H "Title: ${TITLE}" \
    -H "Priority: ${PRIORITY}" \
    -H "Tags: ${TAGS}" \
    -d "${MESSAGE}" \
    "${NTFY_URL}" 2>&1)

  if [[ $? -eq 0 ]]; then
    echo "✓ Notification sent: ${MESSAGE:0:50}..." # Truncate for terminal output
  else
    echo "✗ Failed to send notification" >&2
  fi
else
  echo "Error: curl not found, cannot send ntfy notification" >&2
fi

# Always play terminal bell as backup
# Write directly to terminal device for better reliability across hook execution contexts
tput bel > /dev/tty