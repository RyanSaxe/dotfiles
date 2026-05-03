#!/usr/bin/env bash
set -Eeuo pipefail

json_input="${1:-}"
if [[ -z "$json_input" && ! -t 0 ]]; then
  json_input="$(cat || true)"
fi

jq_value() {
  local expression=$1
  if [[ -z "$json_input" ]] || ! command -v jq > /dev/null 2>&1; then
    return 0
  fi

  jq -r "$expression // empty" 2> /dev/null <<< "$json_input" || true
}

first_value() {
  local value
  for value in "$@"; do
    if [[ -n "$value" && "$value" != "null" ]]; then
      printf '%s' "$value"
      return 0
    fi
  done
}

source_name="${AI_AGENT_SOURCE:-}"
hook_event="$(jq_value '.hook_event_name // .hookEventName')"
notification_type="$(jq_value '.notification_type // .notificationType')"
codex_notify_type="$(jq_value '.type')"
session_id="$(jq_value '.session_id // .sessionId // ."session-id"')"
turn_id="$(jq_value '.turn_id // .turnId // ."turn-id"')"
cwd="$(jq_value '.cwd')"
tool_name="$(jq_value '.tool_name // .toolName')"
message_field="$(jq_value '.message // .body // .text // .question // .error.message')"
title_field="$(jq_value '.title')"
description_field="$(jq_value '.tool_input.description // .toolArgs.description')"
error_type="$(jq_value '.error // .error.name // .error_context // .errorContext')"

hook_event="${hook_event:-$codex_notify_type}"
source_name="${source_name:-$(jq_value '.source')}"
source_name="${source_name:-agent}"

case "$source_name" in
  claude) source_title="Claude Code" ;;
  codex) source_title="Codex CLI" ;;
  copilot) source_title="Copilot CLI" ;;
  *) source_title="AI Agent" ;;
esac

category="attention"
case "$hook_event:$notification_type" in
  Stop:* | agentStop:* | agent-turn-complete:*) category="complete" ;;
  StopFailure:* | ErrorOccurred:* | errorOccurred:*) category="error" ;;
  PermissionRequest:* | permissionRequest:* | approval-requested:* | *:permission_prompt) category="permission" ;;
  Elicitation:* | plan-mode-prompt:* | request-user-input:* | *:elicitation_dialog) category="input" ;;
  PreToolUse:* | *:agent_idle | *:idle_prompt) category="input" ;;
  *:agent_completed) category="complete" ;;
esac

case "$category" in
  complete)
    title="${source_title}: Turn complete"
    message="Agent finished a turn"
    priority="default"
    tags="white_check_mark,robot"
    ;;
  error)
    title="${source_title}: Turn failed"
    message="$(first_value "$message_field" "$error_type" "Agent turn failed")"
    priority="high"
    tags="warning,robot"
    ;;
  permission)
    title="${source_title}: Permission needed"
    message="$(first_value "$message_field" "$description_field" "Permission needed for ${tool_name:-a tool}")"
    priority="high"
    tags="bell,robot"
    ;;
  input)
    title="${source_title}: Input needed"
    message="$(first_value "$message_field" "$description_field" "Agent is waiting for input")"
    priority="high"
    tags="bell,robot"
    ;;
  *)
    title="$(first_value "$title_field" "${source_title}: Attention needed")"
    message="$(first_value "$message_field" "$description_field" "Agent needs attention")"
    priority="default"
    tags="bell,robot"
    ;;
esac

if [[ -n "$cwd" && "$cwd" != "$HOME" ]]; then
  message="[$(basename "$cwd")] $message"
fi

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/ai-harness"
debounce_seconds="${AI_HARNESS_NOTIFY_DEBOUNCE_SECONDS:-2}"
dedupe_scope="$(first_value "$turn_id" "$session_id" "$cwd" "global")"
dedupe_key="${source_name}:${dedupe_scope}:${category}"

should_skip_duplicate() {
  local key=$1
  local ttl=$2

  [[ "$ttl" == "0" ]] && return 1
  [[ "$ttl" =~ ^[0-9]+$ ]] || ttl=2
  mkdir -p "$cache_dir" 2> /dev/null || return 1

  local now hash file last
  now="$(date +%s)"
  hash="$(printf '%s' "$key" | cksum | awk '{print $1}')"
  file="${cache_dir}/notify-${hash}"

  if [[ -f "$file" ]]; then
    read -r last < "$file" || last=0
    if [[ "$last" =~ ^[0-9]+$ ]] && ((now - last < ttl)); then
      return 0
    fi
  fi

  printf '%s\n' "$now" > "$file" 2> /dev/null || true
  return 1
}

emit_bell() {
  [[ "${AI_HARNESS_DISABLE_BELL:-0}" == "1" ]] && return 0

  if [[ -n "${NVIM:-}" ]] && command -v nvim > /dev/null 2>&1; then
    nvim --server "$NVIM" --remote-expr 'execute("lua io.stderr:write(\"\\007\")")' > /dev/null 2>&1 && return 0
  fi

  if [[ -n "${AI_HARNESS_BELL_TTY:-}" && -w "${AI_HARNESS_BELL_TTY:-}" ]]; then
    printf '\a' > "$AI_HARNESS_BELL_TTY" 2> /dev/null && return 0
  fi

  if [[ -n "${TMUX_PANE:-}" ]] && command -v tmux > /dev/null 2>&1; then
    local pane_tty
    pane_tty="$(tmux display-message -p -t "$TMUX_PANE" '#{pane_tty}' 2> /dev/null || true)"
    if [[ -n "$pane_tty" && -w "$pane_tty" ]]; then
      printf '\a' > "$pane_tty" 2> /dev/null && return 0
    fi
  fi

  if [[ -w /dev/tty ]]; then
    printf '\a' > /dev/tty 2> /dev/null && return 0
  fi

  printf '\a' >&2
}

send_ntfy() {
  [[ "${AI_HARNESS_DISABLE_NTFY:-0}" == "1" ]] && return 0
  command -v curl > /dev/null 2>&1 || return 0

  local ntfy_url=""
  if [[ -n "${AI_HARNESS_NTFY_URL:-}" ]]; then
    ntfy_url="$AI_HARNESS_NTFY_URL"
  elif [[ -n "${AI_HARNESS_NTFY_TOPIC:-}" ]]; then
    ntfy_url="https://ntfy.sh/${AI_HARNESS_NTFY_TOPIC}"
  elif [[ -n "${CLAUDE_NOTIFICATION_ID:-}" ]]; then
    ntfy_url="https://ntfy.sh/ai-agent-notification-${CLAUDE_NOTIFICATION_ID}"
  fi

  [[ -n "$ntfy_url" ]] || return 0

  curl -fsS \
    -H "Title: ${title}" \
    -H "Priority: ${priority}" \
    -H "Tags: ${tags}" \
    --data-binary "$message" \
    "$ntfy_url" \
    > /dev/null 2>&1 || true
}

if should_skip_duplicate "$dedupe_key" "$debounce_seconds"; then
  exit 0
fi

emit_bell
send_ntfy
