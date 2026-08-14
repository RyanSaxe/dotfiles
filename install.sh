#!/bin/sh
# One-command setup. Run from the repo root on a fresh machine or an old one:
#
#   ./install.sh              interactive: choose tiers, then install
#   ./install.sh core         non-interactive: install the named tiers
#   ./install.sh core agents
#
# Re-running updates: packages upgrade to current versions and symlinks are
# restowed. Every step is idempotent.
set -eu

OS="$(uname -s)"

# ---------------------------------------------------------------- helpers
brew_install() {
  # brew install upgrades outdated formulas and skips current ones, so this
  # doubles as the update path.
  if [ "$#" -gt 0 ]; then brew install "$@"; fi
}

apt_install() {
  if [ "$#" -gt 0 ]; then sudo apt-get install -y "$@"; fi
}

ask() {
  printf '%s [y/N] ' "$1"
  read -r answer
  case "$answer" in [yY]*) return 0 ;; *) return 1 ;; esac
}

ensure_package_manager() {
  case "$OS" in
  Darwin)
    if ! command -v brew >/dev/null 2>&1; then
      echo "installing homebrew..."
      NONINTERACTIVE=1 /bin/bash -c \
        "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi
    # A fresh brew is not on PATH yet.
    if [ -x /opt/homebrew/bin/brew ]; then
      eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [ -x /usr/local/bin/brew ]; then
      eval "$(/usr/local/bin/brew shellenv)"
    fi
    ;;
  Linux)
    sudo apt-get update
    ;;
  *)
    echo "error: unsupported OS: $OS" >&2
    exit 1
    ;;
  esac
}

# ------------------------------------------------------------------- tiers
# System packages per tier and OS, named per package manager. Stow packages
# live in tiers/*.txt.

# zsh plugins are shallow git clones into one fixed path, sourced by .zshrc.
# One mechanism on every OS — brew and apt disagree on names and paths.
clone_plugin() {
  dir="$HOME/.local/share/zsh/plugins/${1##*/}"
  if [ -d "$dir/.git" ]; then
    git -C "$dir" pull --quiet --ff-only
  else
    mkdir -p "${dir%/*}"
    git clone --quiet --depth 1 "https://github.com/$1" "$dir"
  fi
}

install_zsh_plugins() {
  clone_plugin zsh-users/zsh-autosuggestions
  clone_plugin zdharma-continuum/fast-syntax-highlighting
  clone_plugin Aloxaf/fzf-tab
}

# The rail TUI (tuis/rail) runs via tsx from its own node_modules.
install_rail() {
  (cd tuis/rail && npm install --no-fund --no-audit --silent)
}

install_tier_packages() {
  case "$1:$OS" in
  core:Darwin)
    brew_install stow git gh git-delta uv starship fzf tmux node bat
    install_zsh_plugins
    install_rail
    ;;
  core:Linux)
    apt_install stow git gh git-delta curl zsh fzf nodejs npm bat
    # uv and starship are not packaged in apt; use the official installers.
    command -v uv >/dev/null 2>&1 || curl -LsSf https://astral.sh/uv/install.sh | sh
    command -v starship >/dev/null 2>&1 || curl -sS https://starship.rs/install.sh | sh -s -- -y
    install_zsh_plugins
    install_rail
    ;;
  mac:Darwin)
    # Hammerspoon is a cask; it hosts the pokemon mascot (see hammerspoon/).
    brew list --cask hammerspoon >/dev/null 2>&1 || brew install --cask hammerspoon
    # sketchybar itself is mac-only; the plugins under sketchybar/ shell out
    # to macOS-only tools (pmset, ipconfig) regardless.
    brew_install sketchybar
    ;;
  *)
    echo "error: unknown tier for $OS: $1" >&2
    exit 1
    ;;
  esac
}

# Stow one package, cleaning up links left behind by files that were renamed
# or deleted since the last run. Stow itself cannot do this: it unstows by
# walking the CURRENT package tree, so links to files no longer in the tree
# are never visited and dangle forever. We keep a manifest of what each
# package stowed last time; anything in the old manifest but not the new tree
# that is now a broken symlink gets removed.
stow_package() {
  target="${DOTFILES_TARGET:-$HOME}"
  manifest_dir="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/manifest"
  manifest="$manifest_dir/$1.txt"
  mkdir -p "$manifest_dir"

  current="$(cd "$1" && find . -type f | sort)"

  if [ -f "$manifest" ]; then
    printf '%s\n' "$current" | comm -23 "$manifest" - | while IFS= read -r gone; do
      link="$target/${gone#./}"
      # Only touch broken symlinks; a real file there is not ours to delete.
      if [ -L "$link" ] && [ ! -e "$link" ]; then
        rm "$link"
        echo "cleaned dangling link: $link"
      fi
    done
  fi

  stow -R -t "$target" "$1"
  printf '%s\n' "$current" >"$manifest"
}

install_tier() {
  if [ "$1" = mac ] && [ "$OS" != Darwin ]; then
    echo "skipping mac tier: not macOS"
    return 0
  fi
  install_tier_packages "$1"
  # Tiers with no stow packages yet have no tiers/<name>.txt.
  if [ -s "tiers/$1.txt" ]; then
    while IFS= read -r pkg; do
      stow_package "$pkg"
    done <"tiers/$1.txt"
  fi
}

# -------------------------------------------------------------------- main
ensure_package_manager

# No tiers on the command line: choose interactively. (An agents tier —
# interactive AI-harness wiring — arrives with the ai-harness rebuild.)
if [ "$#" -eq 0 ]; then
  set -- core
  if [ "$OS" = Darwin ] && ask "install the mac tier (GUI apps)?"; then
    set -- "$@" mac
  fi
fi

for tier in "$@"; do
  echo "==> $tier"
  install_tier "$tier"
done

# Render the theme so every consumer has colors from the first shell.
if [ -x "$HOME/.local/bin/theme" ]; then
  "$HOME/.local/bin/theme" apply
fi

# Rebuild bat's theme cache now that the vendored Catppuccin tmThemes are
# stowed in; apt names the binary batcat (see zsh/aliases.zsh for the alias).
if command -v bat >/dev/null 2>&1; then
  bat cache --build
elif command -v batcat >/dev/null 2>&1; then
  batcat cache --build
fi

# The commit gate for working on this repo (see README: Development).
uv tool install --quiet prek
git config core.hooksPath .githooks

echo
echo "done. re-run any time to update."
