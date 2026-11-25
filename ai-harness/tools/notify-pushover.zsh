#!/usr/bin/env zsh
# Sends a Pushover push for the agent hook event on stdin: a finished turn, a
# permission prompt or question, or a failed turn. Claude Code, Codex and
# Antigravity CLI call it from their hooks, with the agent's name as $1.
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
if [[ $agent == Antigravity ]] || jq -e 'has("hookEventName")' <<<"$event" >/dev/null 2>&1; then
  is_antigravity=1
fi
finish() {
  ((is_antigravity)) && printf '{}\n'
  exit 0
}

secrets=$HOME/.config/sops-nix/secrets
read_secret() {
  local val=""
  [[ -s $secrets/$1 ]] && val=$(<"$secrets/$1")
  [[ -n $val ]] || val=$(security find-generic-password -s pushover -a "$2" -w 2>/dev/null)
  print -r -- "$val"
}
user=${PUSHOVER_USER:-$(read_secret pushover-user user)}
token=${PUSHOVER_TOKEN:-$(read_secret pushover-token token)}
[[ -n $user && -n $token ]] || finish

if (($+commands[ioreg])); then
  idle=$(ioreg -c IOHIDSystem -d 4 | awk '/HIDIdleTime/ { print int($NF / 1000000000); exit }')
  idle_limit=${PUSHOVER_IDLE:-60}
  [[ $idle_limit == <-> ]] || idle_limit=60
  ((${idle:-0} >= idle_limit)) || finish
fi

# Each event's own words: Claude Code sends Stop, Notification and
# StopFailure, Codex sends Stop and PermissionRequest, and Antigravity sends
# camelCase Stop. A Stop that another hook continued has not ended the turn.
fields=$(jq -r '
  def nonempty: strings | select(length > 0);
  if (.stop_hook_active // .continuationActive) then empty
  elif (.hook_event_name // .hookEventName) == "Stop" then
    if ((.terminationReason // "") | ascii_downcase) == "error" then
      "failed", (first(.error | nonempty) // "")
    elif ((.terminationReason // "") | ascii_downcase) == "user_canceled" then
      empty
    else
      "done", (first((.last_assistant_message, .lastAssistantMessage) | nonempty) // "")
    end
  elif .hook_event_name == "Notification" then
    (first(.title | nonempty) // "needs you"),
    (first(.message | nonempty) // "")
  elif .hook_event_name == "StopFailure" then
    ((first(.error | nonempty) | "failed: \(.)") // "failed"),
    (first((.error_details, .last_assistant_message) | nonempty) // "")
  elif .hook_event_name == "PermissionRequest" then
    "wants permission",
    (first(((.tool_input | objects | .description, .command), .tool_name) | nonempty) // "")
  else empty end
  | gsub("[\r\n]+"; " ")' <<<"$event" 2>/dev/null) || finish
[[ -n $fields ]] || finish
what=${fields%%$'\n'*}
if [[ $fields == *$'\n'* ]]; then
  message=${fields#*$'\n'}
else
  message=""
fi

[[ ${message//[[:space:]]/} == "" ]] && message=""

# Antigravity's Stop payload omits the assistant's reply (it sends only
# lastUserInput and transcriptPath), so read the last non-empty reply from
# the transcript instead of echoing the user's own prompt back.
if [[ -z $message && $what == done ]]; then
  transcript=$(jq -r '.transcriptPath // empty' <<<"$event" 2>/dev/null)
  if [[ -n $transcript ]]; then
    transcript=${transcript/#\~/$HOME}
    if [[ -r $transcript ]]; then
      message=$(jq -Rr 'fromjson? | select(type == "object" and .type == "PLANNER_RESPONSE" and (.content | type) == "string" and (.content | test("\\S"))) | .content | gsub("[\r\n]+"; " ")' "$transcript" 2>/dev/null | tail -n 1)
    fi
  fi
fi

cwd=$(jq -r 'first((.cwd, .workspacePaths[0]?) | strings | select(length > 0)) // empty' <<<"$event" 2>/dev/null)
project=$(git -C "${cwd:-.}" rev-parse --show-toplevel 2>/dev/null)
project=${${project:-${cwd:-$PWD}}:t}
[[ $project == / ]] && project=""
title="${project:+${project} · }${agent:+${agent} }${what}"

# Pushover rejects a title over 250 characters or a message over 1,024 characters.
curl -fsS --max-time 10 https://api.pushover.net/1/messages.json \
  --form-string "token=$token" --form-string "user=$user" \
  --form-string "title=${title:0:250}" \
  --form-string "message=${${message:0:1000}:-(no message)}" \
  >/dev/null 2>&1 &|
finish
