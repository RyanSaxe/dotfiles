#!/usr/bin/env bash
# PostToolUse hook for TodoWrite tool
# Reminds Claude to check skills only when tasks are marked in_progress

set -euo pipefail

# Read input from stdin
input=$(cat)

# Check if any tasks are in_progress
has_in_progress=$(echo "$input" | jq -r '.tool_input.todos[]? | select(.status=="in_progress") | .content' 2>/dev/null)

# Only provide skill reminder if there are in_progress tasks
if [[ -n "$has_in_progress" ]]; then
  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": "<IMPORTANT>You have tasks marked as in_progress. Review your available skills and invoke any that are relevant to the current in_progress task(s) using the Skill tool.</IMPORTANT>"
  }
}
EOF
else
  echo "{}"
fi

exit 0
