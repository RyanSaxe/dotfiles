#!/usr/bin/env bash
# PostToolUse hook for TodoWrite tool
# Triggers after TodoWrite completes - perfect timing to remind about skills
# before starting the next task

set -euo pipefail

# Read input from stdin (PostToolUse provides tool execution context)
# Not currently used, but available for future enhancements
input=$(cat)

# Output JSON with skill activation reminder
# This fires after Claude updates the todo list (starting or completing tasks)
cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": "<IMPORTANT>Before starting the next task, check if any of your available skills are relevant and invoke all appropriate ones using the Skill tool</IMPORTANT>"
  }
}
EOF

exit 0
