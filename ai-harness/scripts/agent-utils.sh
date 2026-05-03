#!/usr/bin/env bash

detect_ai_agent_for_tty() {
  local tty="$1"
  local tty_name="${tty##*/}"

  ps -t "$tty_name" -o comm= -o args= 2> /dev/null | awk '
    {
      comm = $1
      sub(/^.*\//, "", comm)
      line = tolower($0)
      if (comm == "claude" || line ~ /(^|[\/[:space:]])claude([[:space:]]|$)/) {
        print "Claude Code"
        found = 1
        exit
      }
      if (comm == "codex" || line ~ /(^|[\/[:space:]])codex([[:space:]]|$)/) {
        print "Codex CLI"
        found = 1
        exit
      }
      if (comm == "copilot" || line ~ /(^|[\/[:space:]])copilot([[:space:]]|$)/) {
        print "Copilot CLI"
        found = 1
        exit
      }
    }
    END { exit found ? 0 : 1 }
  '
}

is_ai_agent_pane() {
  detect_ai_agent_for_tty "$1" > /dev/null
}

get_ai_agent_panes() {
  local sep=$'\t'
  local format="#{session_name}:#{window_index}.#{pane_index}${sep}#{pane_tty}${sep}#{pane_title}${sep}#{window_bell_flag}${sep}#{pane_id}"
  local location tty title bell pane_id agent_name

  tmux list-panes -a -F "$format" \
    | while IFS=$'\t' read -r location tty title bell pane_id; do
      agent_name=""
      title="${title//|/-}"
      if agent_name="$(detect_ai_agent_for_tty "$tty")"; then
        echo "${location}|${tty}|${title}|${bell}|${pane_id}|${agent_name}"
      fi
    done
}

get_bell_panes() {
  local sep=$'\t'
  local format="#{session_name}:#{window_index}.#{pane_index}${sep}#{pane_tty}${sep}#{pane_title}${sep}#{window_bell_flag}${sep}#{pane_id}"
  local location tty title bell pane_id

  tmux list-panes -a -F "$format" \
    | while IFS=$'\t' read -r location tty title bell pane_id; do
      title="${title//|/-}"

      if [[ "$bell" == "1" ]]; then
        echo "${location}|${tty}|${title}|${bell}|${pane_id}"
      fi
    done
}

format_pane() {
  local location="$1"
  local title="$2"
  local bell="$3"
  local pane_id="${4:-}"
  local label="${5:-}"

  local reset="\033[0m"
  local dim="\033[90m"
  local display_title="$title"
  [[ -n "$label" ]] && display_title="${label} - ${title}"

  if [[ "$bell" == "1" ]]; then
    local orange="\033[38;5;208m"
    printf "%b%-20s%b %b- %s%b\n" "$orange" "$location" "$reset" "$dim" "$display_title" "$reset"
  else
    printf "%-20s %b- %s%b\n" "$location" "$dim" "$display_title" "$reset"
  fi
}

format_ai_agent_pane() {
  format_pane "$1" "$2" "$3" "$4" "$5"
}

switch_to_pane() {
  local target_location="$1"

  if [[ -z "$target_location" ]]; then
    echo "Error: No target location provided"
    return 1
  fi

  local session="${target_location%%:*}"
  local window_pane="${target_location#*:}"
  local window="${window_pane%%.*}"
  local pane="${window_pane#*.}"

  if tmux switch-client -t "$session" 2> /dev/null || tmux attach-session -t "$session"; then
    tmux select-window -t "$session:$window"
    tmux select-pane -t "$session:$window.$pane"
    return 0
  fi

  echo "Error: Could not switch to $target_location"
  return 1
}

resolve_pane_id() {
  local input="$1"

  if [[ -z "$input" && -n "$TMUX" ]]; then
    tmux display -p '#{pane_id}'
    return
  fi

  if [[ "$input" == %* ]]; then
    tmux list-panes -a -F '#{pane_id}' | grep -qx "$input" && {
      echo "$input"
      return
    }
    return 1
  fi

  if [[ "$input" == *:*.* ]]; then
    tmux display -p -t "$input" '#{pane_id}' 2> /dev/null && return 0
    return 1
  fi

  if [[ "$input" == /dev/* ]]; then
    tmux list-panes -a -F '#{pane_tty} #{pane_id}' \
      | awk -v tty="$input" '$1==tty {print $2; found=1} END{exit !found}'
    return $?
  fi

  return 1
}
