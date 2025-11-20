#!/usr/bin/env bash
# PreToolUse hook for TodoWrite tool
# Triggers before TodoWrite completes

set -euo pipefail

# Read input from stdin (PostToolUse provides tool execution context)
# Not currently used, but available for future enhancements
input=$(cat)

# Output JSON with skill activation reminder
# This fires before Claude updates the todo list (starting or completing tasks)
cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "additionalContext": "<IMPORTANT>Before you update your TODOs, read all the available skills and do the following: For all incomplete TODO items, determine whether you have skills you can use to help you complete it. If you do, update the TODO item to specifically say "use Skill(s) [insert relevant skills here] to [todo list item]</IMPORTANT>"
  }
}
EOF

exit 0
