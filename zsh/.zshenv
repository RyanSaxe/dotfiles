# ~/.zshenv
# Sourced for ALL zsh invocations (interactive, non-interactive, login, non-login)
# Keep this minimal and fast.

# ----- Locale (optional, but common) -----
export LANG="en_US.UTF-8"
export LC_ALL="en_US.UTF-8"

# ----- OS-specific PATH / Homebrew setup -----
case "$OSTYPE" in
  darwin*) # macOS
    # Apple Silicon Homebrew
    if [[ -x /opt/homebrew/bin/brew ]]; then
      eval "$(/opt/homebrew/bin/brew shellenv)"
    # Intel macOS Homebrew
    elif [[ -x /usr/local/bin/brew ]]; then
      eval "$(/usr/local/bin/brew shellenv)"
    fi
    ;;

  linux-gnu* | linux*)
    # Ubuntu-style defaults (no Homebrew / Linuxbrew nonsense)
    # Prepend common user/local paths; avoid duplicates by checking first.
    path_add() {
      [[ ":$PATH:" == *":$1:"* ]] || PATH="$1:$PATH"
    }

    path_add "$HOME/.local/bin"
    path_add "/usr/local/sbin"
    path_add "/usr/local/bin"
    export PATH
    ;;
esac
. "$HOME/.cargo/env"
