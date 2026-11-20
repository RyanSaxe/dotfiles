#!/usr/bin/env zsh
# Sends a Pushover push for the agent hook event on stdin: a finished turn, a
# permission prompt or question, or a failed turn. Claude Code and Codex call
# it from their hooks, with the agent's name as $1.
#
# The keys come from PUSHOVER_USER and PUSHOVER_TOKEN, from the secrets each
# home switch decrypts into ~/.config/sops-nix/secrets, or from the login
# keychain (service "pushover", accounts "user" and "token"). Without them it
# does nothing. On macOS it stays quiet while the keyboard or mouse was used
# in the last PUSHOVER_IDLE seconds (60), because an agent ends a turn every
# time it answers someone sitting at the computer.
#
# A hook must never hold up or fail the agent, so this sends in the background
# and always exits 0. Antigravity hooks expect JSON on stdout, while Claude
# Code and Codex expect no output.

event=$(cat)
agent=$1

# Antigravity sends camelCase hook payloads (hookEventName) and requires JSON
# on stdout. Emit {} on every exit path for it.
is_antigravity=0
if jq -e 'has("hookEventName")' <<<"$event" >/dev/null 2>&1; then
  is_antigravity=1
fi
finish() {
  ((is_antigravity)) && printf '{}\n'
  exit 0
}

secrets=$HOME/.config/sops-nix/secrets
user=${PUSHOVER_USER:-$(cat $secrets/pushover-user 2>/dev/null || security find-generic-password -s pushover -a user -w 2>/dev/null)}
token=${PUSHOVER_TOKEN:-$(cat $secrets/pushover-token 2>/dev/null || security find-generic-password -s pushover -a token -w 2>/dev/null)}
[[ -n $user && -n $token ]] || finish

if (($+commands[ioreg])); then
  idle=$(ioreg -c IOHIDSystem -d 4 | awk '/HIDIdleTime/ { print int($NF / 1000000000); exit }')
  ((${idle:-0} >= ${PUSHOVER_IDLE:-60})) || finish
fi

# Each event's own words: Claude Code sends Stop, Notification and
# StopFailure, Codex sends Stop and PermissionRequest, and Antigravity sends
# camelCase Stop. A Stop that another hook continued has not ended the turn.
fields=$(jq -r '
  if (.stop_hook_active // .continuationActive) then empty
  elif (.hook_event_name // .hookEventName) == "Stop" then
    if (.terminationReason // "") == "ERROR" then
      "failed", (.error // "")
    elif (.terminationReason // "") == "USER_CANCELED" then
      empty
    else
      "done", (.last_assistant_message // .lastUserInput // "")
    end
  elif .hook_event_name == "Notification" then (.title // "needs you"), (.message // "")
  elif .hook_event_name == "StopFailure" then "failed: \(.error)", (.error_details // .last_assistant_message // "")
  elif .hook_event_name == "PermissionRequest" then "wants permission",
    (.tool_input.description // .tool_input.command // .tool_name // "")
  else empty end
  | gsub("\n"; " ")' <<<"$event" 2>/dev/null) || finish
[[ -n $fields ]] || finish
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
finish
