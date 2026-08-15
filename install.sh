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

ensure_zsh_login_shell() {
  # macOS ships zsh (default since Catalina) and the Linux core tier
  # apt-installs it, but neither makes it the LOGIN shell on a machine
  # that started on bash — and everything here assumes zsh.
  case "$SHELL" in
  */zsh) return 0 ;;
  esac
  zsh_path="$(command -v zsh || true)"
  if [ -z "$zsh_path" ]; then
    echo "warning: zsh not found; login shell unchanged" >&2
    return 0
  fi
  # chsh refuses shells missing from /etc/shells.
  grep -qx "$zsh_path" /etc/shells 2>/dev/null ||
    printf '%s\n' "$zsh_path" | sudo tee -a /etc/shells >/dev/null
  chsh -s "$zsh_path"
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

# One inventory per package manager. POSIX sh has no arrays: these are
# space-separated words, expanded unquoted on purpose (hence the shellcheck
# disables at each use).
CORE_BREW_FORMULAS='stow git gh git-delta uv starship fzf tmux node bat'
CORE_APT_PACKAGES='stow git gh git-delta curl zsh fzf nodejs npm bat'
MAC_BREW_FORMULAS='sketchybar'
MAC_BREW_CASKS='aerospace'
ZSH_PLUGINS='zsh-users/zsh-autosuggestions zdharma-continuum/fast-syntax-highlighting Aloxaf/fzf-tab'
RAIL_DIR='tuis/rail'

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
  for plugin in $ZSH_PLUGINS; do
    clone_plugin "$plugin"
  done
}

# The rail TUI (tuis/rail) runs via tsx from its own node_modules.
install_rail() {
  (cd "$RAIL_DIR" && npm install --no-fund --no-audit --silent)
}

install_tier_packages() {
  case "$1:$OS" in
  core:Darwin)
    # shellcheck disable=SC2086
    brew_install $CORE_BREW_FORMULAS
    ensure_zsh_login_shell
    install_zsh_plugins
    install_rail
    ;;
  core:Linux)
    # shellcheck disable=SC2086
    apt_install $CORE_APT_PACKAGES
    # uv and starship are not packaged in apt; use the official installers.
    command -v uv >/dev/null 2>&1 || curl -LsSf https://astral.sh/uv/install.sh | sh
    command -v starship >/dev/null 2>&1 || curl -sS https://starship.rs/install.sh | sh -s -- -y
    ensure_zsh_login_shell
    install_zsh_plugins
    install_rail
    ;;
  mac:Darwin)
    # sketchybar itself is mac-only; the plugins under sketchybar/ shell out
    # to macOS-only tools (pmset, ipconfig) regardless. It lives in the
    # felixkratz tap, which newer brews refuse to install from untrusted
    # (`brew trust` doesn't exist on older brews — hence the guard).
    brew tap felixkratz/formulae
    brew trust felixkratz/formulae 2>/dev/null || true
    # shellcheck disable=SC2086
    brew_install $MAC_BREW_FORMULAS
    # aerospace is a cask in nikitabobko's tap; install skips when present
    # (casks error on reinstall, unlike formulas).
    brew tap nikitabobko/tap
    brew trust nikitabobko/tap 2>/dev/null || true
    for cask in $MAC_BREW_CASKS; do
      brew list --cask "$cask" >/dev/null 2>&1 || brew install --cask "$cask"
    done
    # Per-machine notch compensation for aerospace's top gap.
    ./aerospace/.config/aerospace/configure.sh
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
