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
dev() {
  local session_name="${1:-$(basename "$PWD")}"
  
  # Check if session already exists
  if tmux has-session -t "$session_name" 2>/dev/null; then
    echo "Session '$session_name' already exists. Attaching..."
    tmux attach-session -t "$session_name"
    return
  fi
  
  # Create new session with first window (nvim)
  tmux new-session -d -s "$session_name" -n "nvim"
  tmux send-keys -t "$session_name:nvim" "nvim" Enter
  
  # Create second window (terminal)
  tmux new-window -t "$session_name" -n "terminal"
  
  # Create third window (logs/misc)
  tmux new-window -t "$session_name" -n "logs"
  
  # Go back to first window and attach
  tmux select-window -t "$session_name:nvim"
  tmux attach-session -t "$session_name"
}

# Switch tmux sessions with fzf (works inside and outside tmux)
ss() {
  local session
  session=$(tmux list-sessions -F "#{session_name}" 2>/dev/null | fzf --prompt="Switch to session: " --height=40% --reverse)
  if [[ -n "$session" ]]; then
    if [[ -n "$TMUX" ]]; then
      # Inside tmux - switch client
      tmux switch-client -t "$session"
    else
      # Outside tmux - attach to session
      tmux attach-session -t "$session"
    fi
  fi
}
