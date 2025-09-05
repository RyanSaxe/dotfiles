# If you come from bash you might have to change your $PATH.
# export PATH=$HOME/bin:$HOME/.local/bin:/usr/local/bin:$PATH

# Path to your Oh My Zsh installation.
export ZSH="$HOME/.oh-my-zsh"

# Set name of the theme to load --- if set to "random", it will
# load a random theme each time Oh My Zsh is loaded, in which case,
# to know which specific one was loaded, run: echo $RANDOM_THEME
# See https://github.com/ohmyzsh/ohmyzsh/wiki/Themes
ZSH_THEME="fino-time-custom"
# remove the virtualenv name getting injected in the terminal directly so the prompt can handle it
export VIRTUAL_ENV_DISABLE_PROMPT=1

# Set list of themes to pick from when loading at random
# Setting this variable when ZSH_THEME=random will cause zsh to load
# a theme from this variable instead of looking in $ZSH/themes/
# If set to an empty array, this variable will have no effect.
# ZSH_THEME_RANDOM_CANDIDATES=( "robbyrussell" "agnoster" )

# Uncomment the following line to use case-sensitive completion.
# CASE_SENSITIVE="true"

# Uncomment the following line to use hyphen-insensitive completion.
# Case-sensitive completion must be off. _ and - will be interchangeable.
# HYPHEN_INSENSITIVE="true"

# Uncomment one of the following lines to change the auto-update behavior
# zstyle ':omz:update' mode disabled  # disable automatic updates
# zstyle ':omz:update' mode auto      # update automatically without asking
# zstyle ':omz:update' mode reminder  # just remind me to update when it's time

# Uncomment the following line to change how often to auto-update (in days).
# zstyle ':omz:update' frequency 13

# Uncomment the following line if pasting URLs and other text is messed up.
# DISABLE_MAGIC_FUNCTIONS="true"

# Uncomment the following line to disable colors in ls.
# DISABLE_LS_COLORS="true"

# Uncomment the following line to disable auto-setting terminal title.
# DISABLE_AUTO_TITLE="true"

# Uncomment the following line to enable command auto-correction.
# ENABLE_CORRECTION="true"

# Uncomment the following line to display red dots whilst waiting for completion.
# You can also set it to another string to have that shown instead of the default red dots.
# e.g. COMPLETION_WAITING_DOTS="%F{yellow}waiting...%f"
# COMPLETION_WAITING_DOTS="true"

# Uncomment the following line if you want to disable marking untracked files
# under VCS as dirty. This makes repository status check for large repositories
# much, much faster.
# DISABLE_UNTRACKED_FILES_DIRTY="true"

# Uncomment the following line if you want to change the command execution time
# stamp shown in the history command output.
# You can set one of the optional three formats:
# "mm/dd/yyyy"|"dd.mm.yyyy"|"yyyy-mm-dd"
# or set a custom format using the strftime function format specifications.
# For more details, see 'man strftime' or 'info strftime'.
# HIST_STAMPS="mm/dd/yyyy"

# Would you like to use another custom folder than $ZSH/custom?
ZSH_CUSTOM="$HOME/.zsh-custom"

# Which plugins would you like to load?
# Standard plugins can be found in $ZSH/plugins/
# Custom plugins may be added to $ZSH_CUSTOM/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
# Add wisely, as too many plugins slow down shell startup.
plugins=(git vi-mode)

source $ZSH/oh-my-zsh.sh

# User configuration

# export MANPATH="/usr/local/man:$MANPATH"

# You may need to manually set your language environment
# export LANG=en_US.UTF-8

# Preferred editor for local and remote sessions
# if [[ -n $SSH_CONNECTION ]]; then
#   export EDITOR='vim'
# else
#   export EDITOR='mvim'
# fi

# Compilation flags
# export ARCHFLAGS="-arch x86_64"

# Set personal aliases, overriding those provided by oh-my-zsh libs,
# plugins, and themes. Aliases can be placed here, though users are encouraged
# to define aliases within the ZSH_CUSTOM folder.
# For a full list of active aliases, run `alias`.
#
# Example aliases
# alias zshconfig="mate ~/.zshrc"
# alias ohmyzsh="mate ~/.oh-my-zsh"

# Enable vi mode
set -o vi

# Vi mode configuration
export KEYTIMEOUT=1

# Better vi mode indicator
function zle-keymap-select {
  if [[ ${KEYMAP} == vicmd ]] ||
     [[ $1 = 'block' ]]; then
    echo -ne '\e[1 q'
  elif [[ ${KEYMAP} == main ]] ||
       [[ ${KEYMAP} == viins ]] ||
       [[ ${KEYMAP} = '' ]] ||
       [[ $1 = 'beam' ]]; then
    echo -ne '\e[5 q'
  fi
}
zle -N zle-keymap-select
zle-line-init() {
    zle -K viins
    echo -ne "\e[5 q"
}
zle -N zle-line-init
echo -ne '\e[5 q'
preexec() { echo -ne '\e[5 q' ;}

. "$HOME/.local/bin/env"
export PATH="/opt/homebrew/opt/openjdk@17/bin:$PATH"

# Auto-activate a .venv by walking up to the nearest git root (no git calls).
autoload -U add-zsh-hook
typeset -gA _VENV_CACHE  # dir -> venv path (or empty)

_auto_activate_venv() {
  local start="$PWD" dir="$PWD" venv=""
  # Cache hit?
  if [[ -n "${_VENV_CACHE[$start]-}" ]]; then
    venv="${_VENV_CACHE[$start]}"
  else
    # Walk up until we hit a git boundary ('.git') or the filesystem root.
    while [[ "$dir" != "/" ]]; do
      [[ -d "$dir/.venv" ]] && { venv="$dir/.venv"; break; }
      # Stop scanning above the repo root
      [[ -e "$dir/.git" ]] && break
      dir="${dir:h}"
    done
    _VENV_CACHE[$start]="$venv"
  fi

  if [[ -n "$venv" ]]; then
    # Only source if it's a different venv than the active one
    if [[ "$VIRTUAL_ENV" != "$venv" ]]; then
      source "$venv/bin/activate"
    fi
  else
    # No venv found, deactivate if one is active
    if [[ -n "$VIRTUAL_ENV" && "$(whence -w deactivate)" ]]; then
      deactivate
    fi

  fi
}

add-zsh-hook chpwd _auto_activate_venv
_auto_activate_venv

# Tmux session management

alias ta="tmux attach"
alias td="tmux detach"

alias tl="tmux list-sessions"
alias tk="tmux kill-session"
alias tK="tmux kill-server"

# Create a new tmux session with predefined windows and programs

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
    tmux new-window -t "$session_name" -n "terminal" -c "$start_dir"
  else
    tmux new-window -t "$session_name" -n "terminal"
  fi

  # Track window names to prevent duplicates
  local window_names=("nvim" "terminal")

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
  
  tmux select-window -t "${session_name}:terminal"
  echo "Session '$session_name' created successfully. Attaching..."
  _tmux_attach_or_switch "${session_name}:terminal"
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


# Cache the CSV output of a function in ~/.cache/custom_scripts/<func>.csv
# Usage:
#   cache_csv [-f|--force] <function_name> [--] [args...]
# - The target function must print CSV to stdout.
# - If --force/-f is given, the function is re-run and the cache is overwritten.
# - Otherwise, the function only runs if the cache file doesn't exist (or is empty).
# - Returns (prints) the absolute path to the cached CSV file.
cache_csv() {
  emulate -L zsh -o pipefail

  # Parse flags
  local force=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -f|--force) force=1; shift ;;
      --) shift; break ;;
      -*) print -u2 "cache_csv: unknown flag: $1"; return 2 ;;
      *) break ;;
    esac
  done

  # Require the function name
  local fn="${1:-}"
  if [[ -z "$fn" ]]; then
    print -u2 "cache_csv: missing <function_name>"
    return 2
  fi
  shift

  # Validate function exists
  if ! typeset -f -- "$fn" >/dev/null; then
    print -u2 "cache_csv: '$fn' is not a defined function"
    return 2
  fi

  # Cache path
  local cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/custom_scripts"
  local outfile="${cache_dir}/${fn}.csv"

  # Ensure directory exists
  mkdir -p "$cache_dir" || {
    print -u2 "cache_csv: failed to create cache dir: $cache_dir"
    return 1
  }

  # Decide whether to (re)generate
  if (( force )) || [[ ! -s "$outfile" ]]; then
    # Write atomically via temp file
    local tmp
    tmp="$(mktemp "${outfile}.XXXXXX")" || {
      print -u2 "cache_csv: failed to create temp file"
      return 1
    }

    # Call the function (with any extra args) and capture CSV
    if "$fn" "$@" >| "$tmp"; then
      mv -f -- "$tmp" "$outfile" || {
        print -u2 "cache_csv: failed to move temp file into place"
        rm -f -- "$tmp"
        return 1
      }
    else
      local rc=$?
      rm -f -- "$tmp"
      print -u2 "cache_csv: function '$fn' failed with exit code $rc"
      return $rc
    fi
  fi

  # Return the cached path
  print -r -- "$outfile"
}

# Fuzzy find and cd into git repositories sorted by last commit date, then open tmux session
# INTERFACE: to [same exact arguments as 'tm']

_to() {
  # Directories to search
  search_dirs=("$HOME/work" "$HOME/projects" "$HOME/generic" "$HOME/Work" "$HOME/Projects" "$HOME/Generic")

  # Date formatting for Linux/macOS
  if date -d @0 "+%Y" >/dev/null 2>&1; then
    date_cmd() { date -d "@$1" "+%Y-%m-%d %H:%M"; }
  else
    date_cmd() { date -r "$1" "+%Y-%m-%d %H:%M"; }
  fi

  # Find all git repos
  repos=()
  for dir in "${search_dirs[@]}"; do
    [[ -d "$dir" ]] && repos+=($(fd .git -t d -H "$dir"))
  done

  repo_roots=($(printf "%s\n" "${repos[@]}" | sed 's|/\.git||' | sort -u))

  # Build table: repo_name<TAB>repo_path<TAB>date
  repo_table=()
  for repo in "${repo_roots[@]}"; do
    if [[ -d "$repo/.git" ]]; then
      last_commit=$(git -C "$repo" log -1 --format="%ct" 2>/dev/null)
      last_commit=${last_commit:-0}
      date_str=$(date_cmd "$last_commit")
      repo_name=$(basename "$repo")
      repo_table+=("${repo_name},${repo},${date_str}")
    fi
  done

  printf "%s\n" "${repo_table[@]}"
}


to() {
  emulate -L zsh
  set -o pipefail

  local -a args=()
  local force=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -f|--force) force=1; shift ;;
      *) args+=("$1"); shift ;;
    esac
  done

  # Build cache file (with or without force)
  local cache_file
  if (( force )); then
    cache_file=$(cache_csv -f _to)
  else
    cache_file=$(cache_csv _to)
  fi

  local selected
  selected=$(
    sort -t, -k3,3r -- "$cache_file" \
    | column -t -s, \
    | fzf --prompt="Select repo: "
  )

  [[ -z "$selected" ]] && return 0

  # Extract repo path (2nd visible column after `column -t`)
  local repo
  repo=$(awk -v FS='[[:space:]]+' '{print $2}' <<<"$selected")
  [[ -z "$repo" ]] && return 0

  tm -n "$repo" "${args[@]}"
}

