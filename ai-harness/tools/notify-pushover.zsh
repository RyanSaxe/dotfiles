#!/bin/zsh
# Sends a Pushover push for the agent hook event on stdin: a finished turn, a
# permission prompt or question, or a failed turn. Claude Code and Codex call
# it from their hooks, with the agent's name as $1.
#
# The keys come from PUSHOVER_USER and PUSHOVER_TOKEN, or from the login
# keychain (service "pushover", accounts "user" and "token"). Without them it
# does nothing. On macOS it stays quiet while the keyboard or mouse was used
# in the last PUSHOVER_IDLE seconds (60), because an agent ends a turn every
# time it answers someone sitting at the computer.
#
# A hook must never hold up or fail the agent, so this prints nothing, sends
# in the background and always exits 0.

event=$(cat)
agent=$1

user=${PUSHOVER_USER:-$(security find-generic-password -s pushover -a user -w 2>/dev/null)}
token=${PUSHOVER_TOKEN:-$(security find-generic-password -s pushover -a token -w 2>/dev/null)}
[[ -n $user && -n $token ]] || exit 0

if (($+commands[ioreg])); then
  idle=$(ioreg -c IOHIDSystem -d 4 | awk '/HIDIdleTime/ { print int($NF / 1000000000); exit }')
  ((${idle:-0} >= ${PUSHOVER_IDLE:-60})) || exit 0
fi

# Each event's own words: Claude Code sends Stop, Notification and
# StopFailure, Codex sends Stop and PermissionRequest. A Stop that another
# hook continued has not ended the turn.
fields=$(jq -r '
  if .stop_hook_active then empty
  elif .hook_event_name == "Stop" then "done", (.last_assistant_message // "")
  elif .hook_event_name == "Notification" then (.title // "needs you"), (.message // "")
  elif .hook_event_name == "StopFailure" then "failed: \(.error)", (.error_details // .last_assistant_message // "")
  elif .hook_event_name == "PermissionRequest" then "wants permission",
    (.tool_input.description // .tool_input.command // .tool_name // "")
  else empty end
  | gsub("\n"; " ")' <<<"$event" 2>/dev/null) || exit 0
[[ -n $fields ]] || exit 0
what=${fields%%$'\n'*}
message=${fields#*$'\n'}

cwd=$(jq -r '.cwd // empty' <<<"$event")
project=$(git -C "${cwd:-.}" rev-parse --show-toplevel 2>/dev/null)
project=${${project:-$cwd}:t}

# Pushover rejects a message over 1,024 characters.
curl -fsS --max-time 10 https://api.pushover.net/1/messages.json \
  --form-string "token=$token" --form-string "user=$user" \
  --form-string "title=$project · $agent $what" \
  --form-string "message=${${message:0:1000}:-(no message)}" \
  >/dev/null 2>&1 &|
exit 0
