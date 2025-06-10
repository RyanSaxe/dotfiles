#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

# ──────────────────────────────────────────────────────
# Colorized logging
log() { printf "\033[1;34m[INFO]\033[0m %s\n" "$*"; }
err() { printf "\033[1;31m[ERR ]\033[0m %s\n" "$*" >&2; }

# ──────────────────────────────────────────────────────
sudo_if_needed() {
  if ((EUID == 0)); then
    "$@"
  else
    sudo "$@"
  fi
}

# ──────────────────────────────────────────────────────
detect_pm() {
  for pm in brew apt; do
    if command -v "$pm" &>/dev/null; then
      echo "$pm"
      return 0
    fi
  done
  err "No supported package manager found (brew or apt)"
  exit 1
}
# NOTE: eventually there will be deps only on brew that are how I like things locally but overkill for a server
BREW_DEPS=(
  neovim ripgrep fzf fd git lazygit node tmux gh python3 ipython3
  openjdk@17 wget git-delta curl zsh
)
APT_DEPS=(
  neovim ripgrep fzf fd-find git build-essential nodejs tmux gh
  python3 ipython3 openjdk-17-jdk wget git-delta curl zsh
)
# NOTE: below is the explanation for each of the above dependencies. They are either here due to commonly being used directly
#       or because :checkhealth in neovim raises warnings/errors if they are not installed.
#
#       neovim: my main IDE for development
#       ripgrep: a variety of plugins leverage ripgrep for searching
#       fzf: a command-line fuzzy finder that is incredibly fast, many plugins use it
#       fd: a fast alternative to find
#       git: needs to be installed for version control
#       lazygit: a terminal UI for git, makes it easier to manage git repositories
#       npm: Node.js package manager, used to install JavaScript packages
#       node: required for launchiung LSP servers and other JavaScript tools
#       tmux: terminal multiplexer, allows multiple terminal sessions in one window
#       gh: GitHub CLI, useful for interacting with GitHub repositories
#       python3: Python 3 interpreter, to ensure python is installed -- uv gets installed later
#       ipython: enhanced interactive Python shell, useful for development -- for nicer REPLs to integrate with neovim
#       openjdk-17: Java Development Kit. This version is required for sonarqube LSP support
#       wget: command-line utility for downloading files from the web
#       git-delta: a syntax-highlighting pager for git, makes diffs more readable
#       build-essential: a package that includes essential tools for building software from source, only needed for linux servers
#       curl: command-line tool for transferring data with URLs, used for fetching scripts and packages
#       zsh: a shell that is more powerful and user-friendly than bash, used as the default shell for many developers

# ──────────────────────────────────────────────────────
install_brew() {
  log "Updating Homebrew…"
  brew update --quiet || true
  log "Installing: ${BREW_DEPS[*]}"
  brew install "${BREW_DEPS[@]}"
}

install_apt() {
  log "Updating apt repositories…"
  sudo_if_needed apt-get update -qq

  log "Installing: ${APT_DEPS[*]}"
  sudo_if_needed apt-get install -y "${APT_DEPS[@]}"

  # fd-find → fd symlink
  if ! command -v fd &>/dev/null; then
    FD_PATH=$(command -v fdfind || true)
    if [[ -n "$FD_PATH" ]]; then
      log "Linking fdfind → fd"
      sudo_if_needed ln -sf "$FD_PATH" /usr/local/bin/fd
    else
      err "fdfind not found; fd will be unavailable"
    fi
  fi

  # lazygit (not in apt)
  if ! install_lazygit; then
    err "lazygit install failed"
    exit 1
  fi
}

# ──────────────────────────────────────────────────────
install_lazygit() {
  log "Installing lazygit…"
  local arch version url tmp

  case "$(uname -m)" in
  x86_64 | amd64) arch="Linux_x86_64" ;;
  aarch64 | arm64) arch="Linux_arm64" ;;
  armv7l | armv6l) arch="Linux_armv6" ;;
  i?86) arch="Linux_32-bit" ;;
  *)
    err "Unsupported CPU architecture: $(uname -m)"
    return 1
    ;;
  esac

  version=$(
    curl -fsSL https://api.github.com/repos/jesseduffield/lazygit/releases/latest |
      grep -Po '"tag_name":\s*"v\K[^"]+'
  ) || {
    err "Could not fetch latest lazygit version"
    return 1
  }

  url="https://github.com/jesseduffield/lazygit/releases/download/v${version}/lazygit_${version}_${arch}.tar.gz"
  tmp=$(mktemp -d)
  curl -fsSL "$url" | tar -xz -C "$tmp" lazygit ||
    {
      err "Failed to download/extract lazygit"
      rm -rf "$tmp"
      return 1
    }

  sudo_if_needed install -m 0755 "$tmp/lazygit" /usr/local/bin/lazygit
  rm -rf "$tmp"

  log "lazygit $(lazygit --version) installed"
}

# ──────────────────────────────────────────────────────
fetch_and_exec() {
  local url=$1
  if command -v curl &>/dev/null; then
    curl -fsSL "$url" | sh
  elif command -v wget &>/dev/null; then
    wget -qO- "$url" | sh
  else
    err "curl & wget missing; installing curl first"
    if [[ "$PM" == "apt" ]]; then
      sudo_if_needed apt-get update -qq
      sudo_if_needed apt-get install -y curl
    elif [[ "$PM" == "brew" ]]; then
      brew install curl
    else
      err "Cannot install curl automatically"
      exit 1
    fi
    curl -fsSL "$url" | sh
  fi
}

# ──────────────────────────────────────────────────────
main() {
  # ── Make sure TERM is valid for tput ─────────────────────
  if [[ -z "${TERM:-}" || "${TERM}" == "unknown" ]]; then
    log "TERM is unset/unknown; defaulting to xterm-256color for this run"
    export TERM=xterm-256color
  fi

  # ── Warn if < 256 colors ────────────────────────────────
  colors=$(tput colors 2>/dev/null || echo 0)
  if ((colors < 256)); then
    err "Terminal only supports $colors colors. Use TERM=xterm-256color for full theming."
  fi

  PM=$(detect_pm)
  log "Using package manager: $PM"

  install_"$PM"

  # Astral UV installer
  fetch_and_exec "https://astral.sh/uv/install.sh"

  # Oh My Zsh (non-interactive)
  export RUNZSH=no
  export CHSH=no
  fetch_and_exec "https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh"

  # Ensure default shell is Zsh
  if command -v zsh &>/dev/null && [[ ! "$SHELL" =~ zsh$ ]]; then
    log "Changing default shell to Zsh for $(whoami)…"
    sudo_if_needed chsh -s "$(command -v zsh)" "$(whoami)"
    log "Default shell set to $(command -v zsh). Logout/Login to apply."
  fi

  log "✅ All done!"
}

main "$@"
