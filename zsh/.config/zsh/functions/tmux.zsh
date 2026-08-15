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
