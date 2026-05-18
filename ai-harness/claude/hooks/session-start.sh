#!/usr/bin/env bash
# SessionStart hook for command activation
# Injects reminder to use commands at session start (startup, resume, clear, compact)

set -euo pipefail

# Output JSON with command activation reminder
cat << EOF
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "<EXTREMELY_IMPORTANT>If you have a custom command that you can use to accomplish your task, invoke it using the SlashCommand tool</EXTREMELY_IMPORTANT>"
  }
}
EOF

exit 0
