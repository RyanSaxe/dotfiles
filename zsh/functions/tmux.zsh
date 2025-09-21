# Tmux session management functions and aliases
# Functions are loaded on-demand via autoload -Uz

# Basic tmux aliases
alias ta="tmux attach"
alias td="tmux detach"
alias tl="tmux list-sessions"
alias tk="tmux kill-session"
alias tK="tmux kill-server"

# Utility: attach or switch depending on whether we're in tmux
_tmux_attach_or_switch() {
  local target="$1"  # can be "session" or "session:window"
  if [[ -n "$TMUX" ]]; then
    tmux switch-client -t "$target"
  else
    # attach can't take a window directly, so select after attaching
    # or use switch-client after attach
    tmux attach-session -t "${target%%:*}"
    [[ "$target" == *:* ]] && tmux switch-client -t "$target"
  fi
}

# Create a new tmux session with predefined windows and programs
tm() {
  # Define shortcut mappings: shortcut -> "command|window_name"
  local -A shortcuts_map=(
    ["py"]="ipython|ipython"
    ["cc"]="claude|claude"
    ["pr"]="gh dash|PRs"
  )

  local session_name="$(basename "$PWD")"
  local start_dir=""
  local commands=()

  # Parse flags and arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -n)
        # If -n points to a directory, use it as the working dir and name the session after its basename.
        if [[ -d "$2" ]]; then
          start_dir="$(cd "$2" && pwd)"
          session_name="$(basename "$start_dir")"
        else
          session_name="$2"
        fi
        shift 2
        ;;
      -c)
        commands+=("$2")
        shift 2
        ;;
      *)
        # Treat remaining arguments as commands/shortcuts
        commands+=("$1")
        shift
        ;;
    esac
  done

  # Check if session already exists
  if tmux has-session -t "$session_name" 2>/dev/null; then
    echo "Session '$session_name' already exists. Attaching..."
    _tmux_attach_or_switch "$session_name"
    return
  fi

  # Create new session with first window (nvim)
  if [[ -n "$start_dir" ]]; then
    tmux new-session -d -s "$session_name" -n "nvim" -c "$start_dir"
  else
    tmux new-session -d -s "$session_name" -n "nvim"
  fi
  tmux send-keys -t "$session_name:nvim" "nvim" Enter

  # Create second window (terminal)
  if [[ -n "$start_dir" ]]; then
    tmux new-window -t "$session_name" -n "zsh" -c "$start_dir"
  else
    tmux new-window -t "$session_name" -n "zsh"
  fi

  # Track window names to prevent duplicates
  local window_names=("nvim" "zsh")

  # Create additional windows for each command
  for cmd in "${commands[@]}"; do
    local window_name
    local command_to_run

    # Check if it's a shortcut
    if [[ -n "${shortcuts_map[$cmd]}" ]]; then
      # Parse "command|window_name" format
      command_to_run="${shortcuts_map[$cmd]%|*}"
      window_name="${shortcuts_map[$cmd]#*|}"
    else
      # Regular command - use first word as window name
      command_to_run="$cmd"
      window_name="${cmd%% *}"
    fi

    # Check for duplicate window names
    if [[ " ${window_names[*]} " =~ " ${window_name} " ]]; then
      echo "Error: Window name '$window_name' already exists in session '$session_name'"
      return 1
    fi
    window_names+=("$window_name")

    # Create the window (respect start_dir if provided)
    if [[ -n "$start_dir" ]]; then
      tmux new-window -t "$session_name" -n "$window_name" -c "$start_dir"
    else
      tmux new-window -t "$session_name" -n "$window_name"
    fi

    # Clear screen first for TUIs; short delay prevents formatting issues
    tmux send-keys -t "$session_name:$window_name" "clear" Enter
    sleep 0.1
    tmux send-keys -t "$session_name:$window_name" "$command_to_run" Enter
  done

  tmux select-window -t "${session_name}:zsh"
  echo "Session '$session_name' created successfully. Attaching..."
  _tmux_attach_or_switch "${session_name}:zsh"
}

# Switch tmux sessions with fzf (works inside and outside tmux)
ts() {
  local session
  session=$(tmux list-sessions -F "#{session_name}" 2>/dev/null | fzf --prompt="Switch to session: " --height=40% --reverse)
  if [[ -n "$session" ]]; then
    _tmux_attach_or_switch "$session"
  else
    echo "No session selected."
  fi
}

# Switch to Claude instance in tmux (with attention indicators)
tc() {
  # Source utility functions (symlinked to this repo)
  local claude_utils_path="${HOME}/.claude/claude-utils.sh"
  if [[ -f "$claude_utils_path" ]]; then
    source "$claude_utils_path"
  else
    echo "Error: claude-utils.sh not found at $claude_utils_path"
    return 1
  fi

  # Ensure required helpers exist
  typeset -f get_claude_panes >/dev/null || { echo "Missing get_claude_panes"; return 1; }
  typeset -f format_claude_pane >/dev/null || { echo "Missing format_claude_pane"; return 1; }
  typeset -f switch_to_claude_pane >/dev/null || { echo "Missing switch_to_claude_pane"; return 1; }

  # Check if we're in tmux
  if [[ -z "$TMUX" ]]; then
    echo "Not in a tmux session"
    return 1
  fi

  # Check fzf availability
  if ! command -v fzf >/dev/null 2>&1; then
    echo "fzf not installed (brew install fzf)"
    return 1
  fi

  # Get all Claude panes
  local claude_panes
  claude_panes=$(get_claude_panes)

  if [[ -z "$claude_panes" ]]; then
    echo "No Claude instances found"
    return 1
  fi

  # Fast path: only one Claude pane
  if [[ $(wc -l <<<"$claude_panes" | tr -d ' ') -eq 1 ]]; then
    local location tty title bell pane_id
    IFS='|' read -r location tty title bell pane_id <<<"$claude_panes"
    switch_to_claude_pane "$location"
    return $?
  fi

  # Build fzf selection list
  local selection
  selection=$(echo "$claude_panes" \
    | while IFS='|' read -r location tty title bell pane_id; do
        format_claude_pane "$location" "$title" "$bell" "$pane_id"
      done \
    | fzf \
        --prompt="Select Claude instance: " \
        --height=40% \
        --reverse \
        --ansi \
        --preview-window=hidden)

  if [[ -z "$selection" ]]; then
    echo "No Claude instance selected."
    return 1
  fi

  local target_location
  # Extract the location (everything before " - ")
  target_location=$(printf '%s' "$selection" | sed 's/ - .*//')
  [[ -z "$target_location" ]] && { echo "Invalid selection"; return 1; }

  # Switch to the selected pane
  switch_to_claude_pane "$target_location"
}

# Switch to any tmux pane with bell notifications
tb() {
  # Source utility functions (symlinked to this repo)
  local claude_utils_path="${HOME}/.claude/claude-utils.sh"
  if [[ -f "$claude_utils_path" ]]; then
    source "$claude_utils_path"
  else
    echo "Error: claude-utils.sh not found at $claude_utils_path"
    return 1
  fi

  # Ensure required helpers exist
  typeset -f get_bell_panes >/dev/null || { echo "Missing get_bell_panes"; return 1; }
  typeset -f format_pane >/dev/null || { echo "Missing format_pane"; return 1; }
  typeset -f switch_to_pane >/dev/null || { echo "Missing switch_to_pane"; return 1; }

  # Check if we're in tmux
  if [[ -z "$TMUX" ]]; then
    echo "Not in a tmux session"
    return 1
  fi

  # Check fzf availability
  if ! command -v fzf >/dev/null 2>&1; then
    echo "fzf not installed (brew install fzf)"
    return 1
  fi

  # Get all panes with bell notifications
  local bell_panes
  bell_panes=$(get_bell_panes)

  if [[ -z "$bell_panes" ]]; then
    echo "No panes with notifications found"
    return 1
  fi

  # Fast path: only one pane with bell
  if [[ $(wc -l <<<"$bell_panes" | tr -d ' ') -eq 1 ]]; then
    local location tty title bell pane_id
    IFS='|' read -r location tty title bell pane_id <<<"$bell_panes"
    switch_to_pane "$location"
    return $?
  fi

  # Build fzf selection list
  local selection
  selection=$(echo "$bell_panes" \
    | while IFS='|' read -r location tty title bell pane_id; do
        format_pane "$location" "$title" "$bell" "$pane_id"
      done \
    | fzf \
        --prompt="Select pane with notification: " \
        --height=40% \
        --reverse \
        --ansi \
        --preview-window=hidden)

  if [[ -z "$selection" ]]; then
    echo "No pane selected."
    return 1
  fi

  local target_location
  # Extract the location (everything before " - ")
  target_location=$(printf '%s' "$selection" | sed 's/ - .*//')
  [[ -z "$target_location" ]] && { echo "Invalid selection"; return 1; }

  # Switch to the selected pane
  switch_to_pane "$target_location"
}