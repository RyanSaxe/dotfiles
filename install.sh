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
install_tier_packages() {
  case "$1:$OS" in
  core:Darwin)
    brew_install stow git gh git-delta uv
    ;;
  core:Linux)
    apt_install stow git gh git-delta curl
    # uv is not packaged in apt; use the official installer.
    command -v uv >/dev/null 2>&1 || curl -LsSf https://astral.sh/uv/install.sh | sh
    ;;
  mac:Darwin)
    brew_install
    ;;
  agents:*)
    ;;
  *)
    echo "error: unknown tier for $OS: $1" >&2
    exit 1
    ;;
  esac
}

install_tier() {
  if [ "$1" = mac ] && [ "$OS" != Darwin ]; then
    echo "skipping mac tier: not macOS"
    return 0
  fi
  install_tier_packages "$1"
  # Restow so re-runs reconcile renames and removals. DOTFILES_TARGET exists
  # so tests can point this at a throwaway directory instead of $HOME.
  # Tiers with no stow packages yet have no tiers/<name>.txt.
  if [ -s "tiers/$1.txt" ]; then
    xargs stow -R -t "${DOTFILES_TARGET:-$HOME}" <"tiers/$1.txt"
  fi
}

# -------------------------------------------------------------------- main
ensure_package_manager

# No tiers on the command line: choose interactively.
if [ "$#" -eq 0 ]; then
  set -- core
  if [ "$OS" = Darwin ] && ask "install the mac tier (GUI apps)?"; then
    set -- "$@" mac
  fi
  if ask "install the agents tier (AI harness)?"; then
    set -- "$@" agents
  fi
fi

for tier in "$@"; do
  echo "==> $tier"
  install_tier "$tier"
done

# The commit gate for working on this repo (see README: Development).
uv tool install --quiet prek
git config core.hooksPath .githooks

echo
echo "done. re-run any time to update."
