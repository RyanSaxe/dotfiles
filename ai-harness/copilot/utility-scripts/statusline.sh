#!/usr/bin/env zsh

set -u

input="$(cat)"

# TokyoNight colors, kept in sync with the Claude status line.
C_CYAN=$'\033[38;2;125;207;255m'
C_MAGENTA=$'\033[38;2;187;154;247m'
C_GREEN=$'\033[38;2;158;206;106m'
C_RED=$'\033[38;2;247;118;142m'
C_DIM=$'\033[38;2;86;95;137m'
C_ORANGE=$'\033[38;2;255;158;100m'
C_YELLOW=$'\033[38;2;224;175;104m'
RESET=$'\033[0m'

jq_value() {
  local filter="$1"
  local fallback="${2:-}"

  jq -r "$filter // \"$fallback\"" <<< "$input" 2> /dev/null
}

format_tokens() {
  local tokens="${1:-0}"

  if ((tokens >= 1000000)); then
    printf "%.1fM" "$((tokens / 1000000.0))"
  elif ((tokens >= 1000)); then
    printf "%.1fk" "$((tokens / 1000.0))"
  else
    printf "%d" "$tokens"
  fi
}

current_dir="$(jq_value '.workspace.current_dir // .cwd' '')"
if [[ -n "$current_dir" ]]; then
  dir_name="$(basename "$current_dir")"
else
  current_dir="$PWD"
  dir_name="~"
fi

git_info=""
if git -C "$current_dir" rev-parse --git-dir > /dev/null 2>&1; then
  branch="$(git -C "$current_dir" branch --show-current 2> /dev/null)"
  [[ -z "$branch" ]] && branch="detached"

  if git -C "$current_dir" diff-index --quiet HEAD -- 2> /dev/null; then
    git_status="ok"
    status_color="$C_GREEN"
  else
    git_status="dirty"
    status_color="$C_RED"
  fi

  git_info=" ${C_DIM}on${RESET} ${C_MAGENTA}${branch}${RESET} ${status_color}${git_status}${RESET}"
fi

model_name="$(jq_value '.model.display_name // .model.id' 'Copilot')"

context_tokens="$(jq_value '.context_window.current_context_tokens // .context_window.total_tokens' '0')"
context_limit="$(jq_value '.context_window.displayed_context_limit // .context_window.context_window_size' '0')"
context_used_pct="$(jq_value '.context_window.current_context_used_percentage // .context_window.used_percentage' '0')"

token_info=""
if [[ "$context_tokens" == <-> && "$context_tokens" -gt 0 ]]; then
  token_display="$(format_tokens "$context_tokens")"
  if [[ "$context_used_pct" == <-> ]]; then
    if ((context_used_pct < 50)); then
      token_color="$C_GREEN"
    elif ((context_used_pct < 75)); then
      token_color="$C_YELLOW"
    else
      token_color="$C_RED"
    fi
    token_info=" ${C_DIM}[ctx: ${RESET}${token_color}${token_display}${RESET}${C_DIM}/${context_used_pct}%]${RESET}"
  elif [[ "$context_limit" == <-> && "$context_limit" -gt 0 ]]; then
    token_info=" ${C_DIM}[ctx: ${RESET}${C_GREEN}${token_display}${RESET}${C_DIM}/$(format_tokens "$context_limit")]${RESET}"
  else
    token_info=" ${C_DIM}[ctx: ${RESET}${C_GREEN}${token_display}${RESET}${C_DIM}]${RESET}"
  fi
fi

remote_info=""
if [[ "$(jq_value '.remote.connected' 'false')" == "true" ]]; then
  remote_name="$(jq_value '.remote.task_name // .remote.repository' 'remote')"
  remote_info=" ${C_DIM}[${RESET}${C_CYAN}cloud${RESET}${C_DIM}: ${remote_name}]${RESET}"
fi

change_info=""
lines_added="$(jq_value '.cost.total_lines_added' '0')"
lines_removed="$(jq_value '.cost.total_lines_removed' '0')"
if [[ "$lines_added" == <-> && "$lines_removed" == <-> ]] && ((lines_added > 0 || lines_removed > 0)); then
  change_info=" ${C_DIM}[${RESET}${C_GREEN}+${lines_added}${RESET} ${C_RED}-${lines_removed}${RESET}${C_DIM}]${RESET}"
fi

premium_requests="$(jq_value '.cost.total_premium_requests' '0')"
premium_info=""
if [[ "$premium_requests" == <-> && "$premium_requests" -gt 0 ]]; then
  premium_info=" ${C_DIM}[req: ${RESET}${C_YELLOW}${premium_requests}${RESET}${C_DIM}]${RESET}"
fi

status_line="${C_DIM}in ${RESET}${C_CYAN}${dir_name}${RESET}"
status_line+="${git_info}"
status_line+=" ${C_DIM}with${RESET} ${C_ORANGE}${model_name}${RESET}"
status_line+="${token_info}${change_info}${premium_info}${remote_info}"

printf "%b\n" "$status_line"
