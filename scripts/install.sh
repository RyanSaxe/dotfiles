#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

log() { printf "\033[1;34m[INFO]\033[0m %s\n" "$*"; }
err() { printf "\033[1;31m[ERR ]\033[0m %s\n" "$*" >&2; }

sudo_if_needed() {
  if ((EUID == 0)); then "$@"; else sudo "$@"; fi
}

detect_pm() {
  for pm in brew apt dnf yum pacman; do
    command -v "$pm" &>/dev/null && {
      echo "$pm"
      return
    }
  done
  err "No supported package manager found"
  exit 1
}

BREW_DEPS=(neovim)
APT_DEPS=(neovim ripgrep fzf fd-find git build-essential)
DNF_DEPS=(neovim ripgrep lazygit fzf fd-find git)
PACMAN_DEPS=(neovim ripgrep lazygit fzf fd git)

install_brew() {
  brew update --quiet || true
  brew install "${BREW_DEPS[@]}"
}

install_apt() {
  sudo_if_needed apt-get update -qq
  sudo_if_needed apt-get install -y "${APT_DEPS[@]}"
  # create fd → fdfind symlink if it doesn’t exist
  command -v fd >/dev/null 2>&1 || sudo_if_needed ln -s "$(command -v fdfind)" /usr/local/bin/fd
}

install_dnf() { sudo_if_needed dnf install -y "${DNF_DEPS[@]}"; }
install_yum() { sudo_if_needed yum install -y "${DNF_DEPS[@]}"; }
install_pacman() {
  sudo_if_needed pacman -Sy --noconfirm "${PACMAN_DEPS[@]}"
}

install_lazygit() {
  log "Installing lazygit…"

  # ---------------- architecture → asset suffix ----------------
  case "$(uname -m)" in
  x86_64 | amd64) asset_suffix="Linux_x86_64" ;;
  aarch64 | arm64) asset_suffix="Linux_arm64" ;;
  armv7l | armv6l) asset_suffix="Linux_armv6" ;;
  i?86) asset_suffix="Linux_32-bit" ;;
  *)
    err "Unsupported CPU architecture: $(uname -m)"
    return 1
    ;;
  esac

  # ---------------- resolve latest tag ----------------
  LAZYGIT_VERSION=$(
    curl -fsSL https://api.github.com/repos/jesseduffield/lazygit/releases/latest |
      grep -Po '"tag_name":\s*"v\K[^"]+'
  ) || {
    err "Unable to query GitHub API"
    return 1
  }

  # ---------------- download + install ----------------
  url="https://github.com/jesseduffield/lazygit/releases/download/\
v${LAZYGIT_VERSION}/lazygit_${LAZYGIT_VERSION}_${asset_suffix}.tar.gz"

  tmp=$(mktemp -d)
  curl -fsSL "$url" | tar -xz -C "$tmp" lazygit || {
    err "Download or extraction failed (URL was $url)"
    rm -rf "$tmp"
    return 1
  }

  sudo_if_needed install -m 0755 "$tmp/lazygit" /usr/local/bin/lazygit
  rm -rf "$tmp"

  log "lazygit $(lazygit --version) installed successfully"
}

fetch_and_exec() {
  local url=$1
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url" | sh
  elif command -v wget >/dev/null 2>&1; then
    wget -qO- "$url" | sh
  else
    err "curl/wget missing; installing curl"
    case $PM in
    apt) sudo_if_needed apt-get update -qq && sudo_if_needed apt-get install -y curl ;;
    dnf | yum) sudo_if_needed $PM install -y curl ;;
    pacman) sudo_if_needed pacman -Sy --noconfirm curl ;;
    brew) brew install curl ;;
    *)
      err "Cannot install curl automatically"
      exit 1
      ;;
    esac
    curl -fsSL "$url" | sh
  fi
}

main() {
  PM=$(detect_pm)
  log "Using package manager: $PM"
  "install_$PM"
  fetch_and_exec "https://astral.sh/uv/install.sh"
  fetch_and_exec "https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh"
  log "System packages installed"
}

main "$@"
