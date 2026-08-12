# Interactive shell configuration. Keybindings follow README: Conventions.

# Repo root, derived from this file's own symlink — works wherever the repo
# lives, with no hardcoded path. %x is the file currently being sourced.
typeset -g DOTFILES_DIR="${${(%):-%x}:A:h:h}"

# ----- history ---------------------------------------------------------
HISTFILE="$HOME/.zsh_history"
HISTSIZE=50000
SAVEHIST=50000
setopt SHARE_HISTORY HIST_IGNORE_ALL_DUPS HIST_REDUCE_BLANKS HIST_VERIFY

# ----- completion ------------------------------------------------------
autoload -Uz compinit && compinit
# Case-insensitive matching.
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'

# ----- functions -------------------------------------------------------
source "$HOME/.config/zsh/functions/vi-mode.zsh"
source "$HOME/.config/zsh/functions/venv.zsh"
vi_mode_init
venv_init

# The prompt owns the venv indicator; activate must not inject its own.
export VIRTUAL_ENV_DISABLE_PROMPT=1

# ----- plugins (cloned by install.sh) ----------------------------------
# Order matters: fzf-tab needs compinit first; syntax highlighting goes last.
ZSH_PLUGINS="$HOME/.local/share/zsh/plugins"

if [[ -r "$ZSH_PLUGINS/fzf-tab/fzf-tab.plugin.zsh" ]]; then
  source "$ZSH_PLUGINS/fzf-tab/fzf-tab.plugin.zsh"
  # Convention: Tab is menu completion. (Bind after vi_mode_init, which resets keymaps.)
  bindkey -M viins '^I' fzf-tab-complete
fi

if [[ -r "$ZSH_PLUGINS/zsh-autosuggestions/zsh-autosuggestions.zsh" ]]; then
  source "$ZSH_PLUGINS/zsh-autosuggestions/zsh-autosuggestions.zsh"
  # Convention: Shift-Tab accepts ghost text.
  bindkey -M viins '^[[Z' autosuggest-accept
fi

if [[ -r "$ZSH_PLUGINS/fast-syntax-highlighting/fast-syntax-highlighting.plugin.zsh" ]]; then
  source "$ZSH_PLUGINS/fast-syntax-highlighting/fast-syntax-highlighting.plugin.zsh"
fi

# ----- prompt ----------------------------------------------------------
command -v starship > /dev/null && eval "$(starship init zsh)"
