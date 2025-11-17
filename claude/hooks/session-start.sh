#!/usr/bin/env bash
# SessionStart hook for skill activation
# Injects reminder to use skills at session start (startup, resume, clear, compact)

set -euo pipefail

# Output JSON with skill activation reminder
cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "<EXTREMELY_IMPORTANT>If you have a skill that you can use to accomplish your task, use it via your Skill tool</EXTREMELY_IMPORTANT>"
  }
}
EOF

exit 0
