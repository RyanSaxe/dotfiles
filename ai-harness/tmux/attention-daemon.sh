#!/usr/bin/env bash
set -Eeuo pipefail
shopt -s nocasematch

script_dir="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
harness_dir="$(cd "$script_dir/.." && pwd)"
notify_script="$harness_dir/notify.sh"

# shellcheck source=agent-utils.sh
source "$script_dir/agent-utils.sh"

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/ai-harness"
lock_dir="$cache_dir/tmux-attention-daemon.lock"
pid_file="$lock_dir/pid"
state_file="$cache_dir/tmux-action-required-panes"

mkdir -p "$cache_dir" 2> /dev/null || true

if ! mkdir "$lock_dir" 2> /dev/null; then
  if [[ -f "$pid_file" ]]; then
    existing_pid="$(cat "$pid_file" 2> /dev/null || true)"
    if [[ -n "$existing_pid" ]] && kill -0 "$existing_pid" 2> /dev/null; then
      exit 0
    fi
  fi

  rm -rf "$lock_dir" 2> /dev/null || true
  mkdir "$lock_dir" 2> /dev/null || exit 0
fi

printf '%s\n' "$$" > "$pid_file"

cleanup() {
  rm -rf "$lock_dir" 2> /dev/null || true
}
trap cleanup EXIT INT TERM

json_escape() {
  local value="${1:-}"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\r'/\\r}"
  printf '%s' "$value"
}

was_waiting() {
  local pane_id="$1"
  [[ -f "$state_file" ]] && grep -Fxq "$pane_id" "$state_file"
}

notify_action_required() {
  local location="$1"
  local tty="$2"
  local title="$3"
  local pane_id="$4"
  local cwd="$5"

  local message="Codex is waiting for input in ${location}"
  local payload
  payload=$(
    printf '{"type":"request-user-input","session_id":"%s","cwd":"%s","title":"%s","message":"%s"}' \
      "$(json_escape "$pane_id")" \
      "$(json_escape "$cwd")" \
      "$(json_escape "$title")" \
      "$(json_escape "$message")"
  )

  AI_AGENT_SOURCE=codex AI_HARNESS_BELL_TTY="$tty" bash "$notify_script" "$payload" > /dev/null 2>&1 || true
}

poll_once() {
  local next_state sep format
  next_state="$(mktemp "${cache_dir}/tmux-action-required-panes.XXXXXX")" || return 0
  sep=$'\t'
  format="#{session_name}:#{window_index}.#{pane_index}${sep}#{pane_tty}${sep}#{pane_title}${sep}#{pane_id}${sep}#{pane_current_path}"

  tmux list-panes -a -F "$format" 2> /dev/null \
    | while IFS=$'\t' read -r location tty title pane_id cwd; do
      [[ -n "$pane_id" && -n "$tty" ]] || continue
      detect_ai_agent_for_tty "$tty" | grep -Fxq "Codex CLI" || continue

      if [[ "$title" == *"Action Required"* ]]; then
        printf '%s\n' "$pane_id" >> "$next_state"

        if ! was_waiting "$pane_id"; then
          notify_action_required "$location" "$tty" "$title" "$pane_id" "$cwd"
        fi
      fi
    done

  mv "$next_state" "$state_file" 2> /dev/null || true
}

if [[ "${1:-}" == "--once" ]]; then
  poll_once
  exit 0
fi

while :; do
  poll_once
  sleep "${AI_HARNESS_TMUX_ATTENTION_INTERVAL:-1}"
done
