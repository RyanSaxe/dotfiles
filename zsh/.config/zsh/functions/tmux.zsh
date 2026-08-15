# Tmux session management functions and aliases
# Functions are loaded on-demand via autoload -Uz

# Sanitize a string to be a valid tmux session name
# tmux does not allow '.' or ':' in session names because:
# - ':' separates session:window in target specifications
# - '.' separates window.pane in target specifications
# Usage: _sanitize_tmux_session_name "my.project:v2" → "my_project-v2"
_sanitize_tmux_session_name() {
  local name="$1"
  # Replace '.' with '_' and ':' with '-'
  name="${name//\./_}"
  name="${name//:/-}"
  print -r -- "$name"
}

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
  # The global accent (prompt, cursor trail, ghostty) follows the project
  # you just landed in; sessions are named after projects.
  (theme pokemon sync "${target%%:*}" >/dev/null 2>&1 &)
}

# Create a new tmux session with predefined windows and programs
tm() {
  # Define shortcut mappings: shortcut -> "command|window_name"
  local -A shortcuts_map=(
    ["py"]="ipython|ipython"
    ["cc"]="claude|claude"
    ["cx"]="codex|codex"
    ["cp"]="copilot|copilot"
    ["pr"]="gh dash|PRs"
  )

  local session_name="$(_sanitize_tmux_session_name "$(basename "$PWD")")"
  local start_dir=""
  local commands=()

  # Parse flags and arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -n)
        # If -n points to a directory, use it as the working dir and name the session after its basename.
        if [[ -d "$2" ]]; then
          start_dir="$(cd "$2" && pwd)"
          session_name="$(_sanitize_tmux_session_name "$(basename "$start_dir")")"
        else
          session_name="$(_sanitize_tmux_session_name "$2")"
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

  # One shell window; anything else (nvim, agents, TUIs) is opened on
  # demand or requested explicitly via commands/shortcuts.
  if [[ -n "$start_dir" ]]; then
    tmux new-session -d -s "$session_name" -n "zsh" -c "$start_dir"
  else
    tmux new-session -d -s "$session_name" -n "zsh"
  fi

  # Track window names to prevent duplicates
  local window_names=("zsh")

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
