# Auto-detect minimal mode for tmux popup windows
# Check if this is a tmux popup or if minimal mode is explicitly requested
if [[ -n "$TMUX_POPUP" ]] || [[ "$ZSH_MODE" == "minimal" ]]; then
    # Get the actual directory where this .zshrc file is located (resolving symlink)
    local zshrc_real="$(readlink -f ~/.zshrc 2>/dev/null || readlink ~/.zshrc)"
    local zshrc_dir="${zshrc_real:h}"
    source "${zshrc_dir}/.zshrc.minimal"
    return
fi

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

# Disable mail checking to prevent "You have mail" messages
# This is zsh's default behavior when /var/mail/$USER exists
unset MAILCHECK

# Setup functions from dotfiles repo
# Get the actual directory where this .zshrc file is located (resolving symlink)
local zshrc_real="$(readlink -f ~/.zshrc 2>/dev/null || readlink ~/.zshrc)"
local zshrc_dir="${zshrc_real:h}"

# Source function files
source "${zshrc_dir}/functions/env.zsh"
source "${zshrc_dir}/functions/tmux.zsh"
source "${zshrc_dir}/functions/venv.zsh"
source "${zshrc_dir}/functions/vi-mode.zsh"
source "${zshrc_dir}/functions/git-repos.zsh"

# Load shared aliases
source "${zshrc_dir}/aliases.zsh"

# Initialize environment loading, vi mode and virtual environment auto-activation
env_init
vi_mode_init
venv_init

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


. "$HOME/.local/bin/env"
export PATH="/opt/homebrew/opt/openjdk@17/bin:$PATH"

# Path to lazy.nvim for neovim plugin development testing
export LAZY_PATH="$HOME/.local/share/nvim/lazy/lazy.nvim"

# Command to manually load full environment if needed from minimal shell
zsh-full() {
  echo "Upgrading to full zsh environment..."
  exec zsh
}

# Commands to force minimal mode
zsh-minimal() {
  export ZSH_MODE="minimal"
  exec zsh
}
