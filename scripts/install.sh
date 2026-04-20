#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

# ──────────────────────────────────────────────────────
# Script directory for finding companion scripts
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ──────────────────────────────────────────────────────
# Colorized logging
log() { printf "\033[1;34m[INFO]\033[0m %s\n" "$*"; }
err() { printf "\033[1;31m[ERR ]\033[0m %s\n" "$*" >&2; }
warn() { printf "\033[1;33m[WARN]\033[0m %s\n" "$*"; }

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
    if command -v "$pm" &> /dev/null; then
      echo "$pm"
      return 0
    fi
  done
  err "No supported package manager found (brew or apt)"
  exit 1
}
# Load package lists from config files
DOTFILES_DIR="$(dirname "$SCRIPT_DIR")"
BREW_DEPS=()
while IFS= read -r line || [[ -n "$line" ]]; do
  # Skip empty lines and comments
  [[ -n "$line" && ! "$line" =~ ^[[:space:]]*# ]] && BREW_DEPS[${#BREW_DEPS[@]}]="$line"
done < "$DOTFILES_DIR/config/brew-packages.txt"

APT_DEPS=()
while IFS= read -r line || [[ -n "$line" ]]; do
  # Skip empty lines and comments
  [[ -n "$line" && ! "$line" =~ ^[[:space:]]*# ]] && APT_DEPS[${#APT_DEPS[@]}]="$line"
done < "$DOTFILES_DIR/config/apt-packages.txt"
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
#       zsh: a shell with a superset of features compared to bash, used as the default shell
#       bat: a cat clone with syntax highlighting so that file outputs are readable and colored
#       codex: OpenAI's terminal coding agent, installed via Homebrew on macOS and npm on Linux
# ──────────────────────────────────────────────────────
install_brew() {
  log "Updating Homebrew…"
  brew update --quiet || true

  # Add required taps for macOS-specific tools
  log "Adding required Homebrew taps…"
  brew tap nikitabobko/tap     # aerospace (tiling window manager)
  brew tap FelixKratz/formulae # sketchybar, borders

  # Separate casks from formulae (casks need --cask flag)
  local casks=()
  local formulae=()
  for pkg in "${BREW_DEPS[@]}"; do
    case "$pkg" in
      aerospace | codex) casks+=("$pkg") ;;
      *) formulae+=("$pkg") ;;
    esac
  done

  # Install formulae
  if [[ ${#formulae[@]} -gt 0 ]]; then
    log "Installing formulae: ${formulae[*]}"
    brew install "${formulae[@]}"
  fi

  # Install casks
  if [[ ${#casks[@]} -gt 0 ]]; then
    log "Installing casks: ${casks[*]}"
    brew install --cask "${casks[@]}"
  fi
}

install_apt() {
  # Check if we're on Ubuntu before adding Ubuntu-specific PPA
  . /etc/os-release 2> /dev/null || true
  if [[ "${ID:-}" = "ubuntu" || "${ID_LIKE:-}" == *ubuntu* ]]; then
    log "Adding Neovim PPA for latest stable (>= 0.11)…"
    sudo_if_needed apt-get update -qq
    sudo_if_needed apt-get install -y software-properties-common
    sudo_if_needed add-apt-repository -y ppa:neovim-ppa/stable
  else
    warn "Skipping Ubuntu PPA on non-Ubuntu system (${ID:-unknown})"
  fi

  log "Updating apt repositories…"
  sudo_if_needed apt-get update -qq

  log "Installing: ${APT_DEPS[*]}"
  # Install packages that are available, skip those that aren't
  for pkg in "${APT_DEPS[@]}"; do
    if sudo_if_needed apt-get install -y "$pkg" 2> /dev/null; then
      log "✓ Installed $pkg"
    else
      warn "⚠ Failed to install $pkg (may not be available in this repository)"
    fi
  done

  # fd-find → fd symlink
  if ! command -v fd &> /dev/null; then
    FD_PATH=$(command -v fdfind || true)
    if [[ -n "$FD_PATH" ]]; then
      log "Linking fdfind → fd"
      sudo_if_needed ln -sf "$FD_PATH" /usr/local/bin/fd
    else
      err "fdfind not found; fd will be unavailable"
    fi
  fi

  # bat → batcat symlink (common on Debian/Ubuntu)
  if ! command -v bat &> /dev/null && command -v batcat &> /dev/null; then
    log "Linking batcat → bat"
    sudo_if_needed ln -sf "$(command -v batcat)" /usr/local/bin/bat
  fi

  # tectonic (not in apt)
  if ! command -v tectonic &> /dev/null; then
    install_tectonic || {
      err "Tectonic install failed"
      exit 1
    }
  else
    log "Tectonic already installed—skipping re-install"
  fi
  # lazygit (not in apt)
  if ! command -v lazygit &> /dev/null; then
    install_lazygit || {
      err "lazygit install failed"
      exit 1
    }
  else
    log "lazygit already installed—skipping re-install"
  fi
  # mermaid-cli (not in apt)

}

# ────────────────────────────────────────────────────────────────────────
# extra source installs that cannot always be done via package managers
# ────────────────────────────────────────────────────────────────────────
install_tectonic() {
  log "Installing latest Tectonic…"
  local version arch deb_arch url deb_name tmpdir
  version=$(curl -fsSL https://api.github.com/repos/tectonic-typesetting/tectonic/releases/latest \
    | grep -Po '"tag_name":\s*"v?\K[^"]+')
  arch=$(dpkg --print-architecture 2> /dev/null || uname -m)
  case "$arch" in
    amd64 | x86_64) deb_arch=amd64 ;;
    arm64 | aarch64) deb_arch=arm64 ;;
    *)
      err "Unsupported architecture: $arch"
      return 1
      ;;
  esac
  deb_name="tectonic_${version}_${deb_arch}.deb"
  url="https://github.com/tectonic-typesetting/tectonic/releases/download/v${version}/${deb_name}"
  tmpdir=$(mktemp -d)
  curl -fsSL -o "$tmpdir/$deb_name" "$url"

  # Install the package and fix any dependency issues
  if ! sudo_if_needed dpkg -i "$tmpdir/$deb_name"; then
    log "Fixing dependencies for tectonic..."
    sudo_if_needed apt-get -f install -y
    sudo_if_needed dpkg -i "$tmpdir/$deb_name"
  fi

  rm -rf "$tmpdir"
  log "Tectonic $version installed successfully."
}
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
    curl -fsSL https://api.github.com/repos/jesseduffield/lazygit/releases/latest \
      | grep -Po '"tag_name":\s*"v\K[^"]+'
  ) || {
    err "Could not fetch latest lazygit version"
    return 1
  }

  url="https://github.com/jesseduffield/lazygit/releases/download/v${version}/lazygit_${version}_${arch}.tar.gz"
  tmp=$(mktemp -d)
  curl -fsSL "$url" | tar -xz -C "$tmp" lazygit \
    || {
      err "Failed to download/extract lazygit"
      rm -rf "$tmp"
      return 1
    }

  sudo_if_needed install -m 0755 "$tmp/lazygit" /usr/local/bin/lazygit
  rm -rf "$tmp"

  log "lazygit $(lazygit --version) installed"
}

install_pokemon_colorscripts() {
  log "Installing Pokémon Colorscripts…"

  # 1) make a temp clone
  local tmp
  tmp=$(mktemp -d)

  log "Cloning into $tmp"
  git clone https://gitlab.com/phoneybadger/pokemon-colorscripts.git "$tmp"

  # 2) from inside that temp clone, run the upstream installer
  pushd "$tmp" > /dev/null || {
    err "Cannot cd to $tmp"
    return 1
  }
  sudo_if_needed bash install.sh
  popd > /dev/null

  # 3) clean up
  rm -rf "$tmp"
}

install_tpm() {
  log "Installing TPM (Tmux Plugin Manager)…"

  local tpm_dir="$HOME/.config/tmux/plugins/tpm"

  if [[ ! -d "$tpm_dir" ]]; then
    git clone https://github.com/tmux-plugins/tpm "$tpm_dir" || {
      err "Failed to clone TPM repository"
      return 1
    }
    log "TPM installed successfully at $tpm_dir"
  else
    log "TPM already installed—skipping re-install"
  fi
}

# ────────────────────────────────────────────────────────────────────────
# Zsh plugin management (declarative via config/zsh-plugins.txt)
# ────────────────────────────────────────────────────────────────────────
install_zsh_plugins() {
  log "Installing Zsh plugins..."
  local zsh_custom="${ZSH_CUSTOM:-$HOME/.zsh-custom}"
  local plugins_dir="$zsh_custom/plugins"
  mkdir -p "$plugins_dir"

  # Read plugin URLs from config file
  while IFS= read -r url || [[ -n "$url" ]]; do
    # Skip empty lines and comments
    [[ -z "$url" || "$url" =~ ^[[:space:]]*# ]] && continue

    # Extract plugin name from URL (e.g., "zsh-autosuggestions" from "...zsh-autosuggestions.git")
    local name="${url##*/}"
    name="${name%.git}"
    local dest="$plugins_dir/$name"

    if [[ -d "$dest" ]]; then
      log "$name already installed—skipping"
    else
      git clone --depth 1 "$url" "$dest" || {
        err "Failed to clone $name"
        continue
      }
      log "✓ Installed $name"
    fi
  done < "$DOTFILES_DIR/config/zsh-plugins.txt"
}

update_zsh_plugins() {
  log "Updating Zsh plugins..."
  local zsh_custom="${ZSH_CUSTOM:-$HOME/.zsh-custom}"
  local plugins_dir="$zsh_custom/plugins"

  # Iterate through all plugin directories and pull updates
  for plugin_dir in "$plugins_dir"/*/; do
    [[ -d "$plugin_dir/.git" ]] || continue
    local name="${plugin_dir%/}"
    name="${name##*/}"
    log "Updating $name..."
    git -C "$plugin_dir" pull --ff-only || warn "Failed to update $name"
  done
}
# ──────────────────────────────────────────────────────
fetch_and_exec() {
  local url=$1
  if command -v curl &> /dev/null; then
    curl -fsSL "$url" | sh
  elif command -v wget &> /dev/null; then
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
  # Handle --update-plugins flag for updating zsh plugins only
  if [[ "${1:-}" == "--update-plugins" ]]; then
    update_zsh_plugins
    return 0
  fi

  # ── Make sure TERM is valid for tput ─────────────────────
  if [[ -z "${TERM:-}" || "${TERM}" == "unknown" ]]; then
    log "TERM is unset/unknown; defaulting to xterm-256color for this run"
    export TERM=xterm-256color
  fi

  # ── Warn if < 256 colors ────────────────────────────────
  colors=$(tput colors 2> /dev/null || echo 0)
  if ((colors < 256)); then
    err "Terminal only supports $colors colors. Use TERM=xterm-256color for full theming."
  fi

  PM=$(detect_pm)
  log "Using package manager: $PM"

  install_"$PM"

  if ! command -v mmdc &> /dev/null; then
    log "Installing Mermaid CLI via npm…"
    sudo_if_needed npm install -g @mermaid-js/mermaid-cli || {
      err "Mermaid CLI install failed"
      exit 1
    }
  else
    log "Mermaid CLI already installed—skipping re-install"
  fi

  # Install ast-grep via npm on Linux only (on macOS it's installed via brew)
  if [[ "$PM" == "apt" ]] && ! command -v ast-grep &> /dev/null && ! command -v sg &> /dev/null; then
    log "Installing ast-grep via npm…"
    sudo_if_needed npm install -g @ast-grep/cli || {
      err "ast-grep install failed"
      exit 1
    }
  else
    if [[ "$PM" == "apt" ]]; then
      log "ast-grep already installed—skipping re-install"
    fi
  fi

  # Install tree-sitter CLI via npm for both macOS and Linux
  # tree-sitter-cli provides the tree-sitter binary needed by Neovim plugins
  if ! command -v tree-sitter &> /dev/null; then
    log "Installing tree-sitter CLI via npm…"
    sudo_if_needed npm install -g tree-sitter-cli || {
      err "tree-sitter CLI install failed"
      exit 1
    }
  else
    log "tree-sitter CLI already installed—skipping re-install"
  fi

  # Install Codex CLI via npm on Linux (on macOS it's installed via brew)
  if [[ "$PM" == "apt" ]] && ! command -v codex &> /dev/null; then
    log "Installing Codex CLI via npm…"
    sudo_if_needed npm install -g @openai/codex || {
      err "Codex CLI install failed"
      exit 1
    }
  else
    if [[ "$PM" == "apt" ]]; then
      log "Codex CLI already installed—skipping re-install"
    fi
  fi

  # Install git-split-diffs via npm on Linux (on macOS it's installed via brew)
  if [[ "$PM" == "apt" ]] && ! command -v git-split-diffs &> /dev/null; then
    log "Installing git-split-diffs via npm…"
    sudo_if_needed npm install -g git-split-diffs || {
      err "git-split-diffs install failed"
      exit 1
    }
  else
    if [[ "$PM" == "apt" ]]; then
      log "git-split-diffs already installed—skipping re-install"
    fi
  fi

  # Install formatters via npm on Linux (on macOS they're installed via brew)
  if [[ "$PM" == "apt" ]]; then
    # prettier - multi-language formatter for JSON, Markdown, etc.
    if ! command -v prettier &> /dev/null; then
      log "Installing prettier via npm…"
      sudo_if_needed npm install -g prettier || {
        err "prettier install failed"
        exit 1
      }
    else
      log "prettier already installed—skipping re-install"
    fi

    # markdownlint-cli - Markdown linter with auto-fix
    if ! command -v markdownlint &> /dev/null; then
      log "Installing markdownlint-cli via npm…"
      sudo_if_needed npm install -g markdownlint-cli || {
        err "markdownlint-cli install failed"
        exit 1
      }
    else
      log "markdownlint-cli already installed—skipping re-install"
    fi

    # stylua - Lua formatter (not available in apt, use npm package)
    if ! command -v stylua &> /dev/null; then
      log "Installing stylua via npm…"
      sudo_if_needed npm install -g @johnnymorganz/stylua-bin || {
        err "stylua install failed"
        exit 1
      }
    else
      log "stylua already installed—skipping re-install"
    fi
  fi

  # Note: dust is only installed via brew on macOS, not available on Linux

  # Astral UV installer
  if ! command -v uv &> /dev/null; then
    fetch_and_exec "https://astral.sh/uv/install.sh"
  else
    log "Astral UV already present—skipping"
  fi

  # Rustup (Rust toolchain installer)
  if ! command -v rustup &> /dev/null; then
    log "Installing Rust via rustup..."
    curl -fsSL https://sh.rustup.rs | sh -s -- -y --no-modify-path
    # Source cargo env for current session so subsequent checks work
    [[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"
  else
    log "Rustup already present—skipping"
  fi

  # Oh My Zsh (non-interactive)
  if [[ ! -d "${ZSH:-$HOME/.oh-my-zsh}" ]]; then
    export RUNZSH=no CHSH=no
    fetch_and_exec "https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh"
  else
    log "Oh My Zsh already installed—skipping re-install"
  fi

  # Zsh plugins (must come after Oh My Zsh)
  install_zsh_plugins || {
    err "Failed to install Zsh plugins"
    exit 1
  }

  # Ensure default shell is Zsh
  if command -v zsh &> /dev/null && [[ ! "$SHELL" =~ zsh$ ]]; then
    log "Changing default shell to Zsh for $(whoami)…"
    sudo_if_needed chsh -s "$(command -v zsh)" "$(whoami)"
    log "Default shell set to $(command -v zsh). Logout/Login to apply."
  fi

  install_pokemon_colorscripts || {
    err "Failed to install Pokémon Colorscripts"
    exit 1
  }

  install_tpm || {
    err "Failed to install TPM"
    exit 1
  }

  # Symlink dotfiles
  log "Setting up dotfiles symlinks..."
  if [[ -f "$SCRIPT_DIR/symlink.sh" ]]; then
    "$SCRIPT_DIR/symlink.sh" || {
      err "Failed to create dotfiles symlinks"
      exit 1
    }
  else
    warn "Symlink script not found at $SCRIPT_DIR/symlink.sh - skipping dotfiles setup"
  fi

  # Configure aerospace notch detection (macOS only)
  if [[ "$PM" == "brew" ]] && [[ -f "$DOTFILES_DIR/aerospace/configure.sh" ]]; then
    log "Configuring aerospace display settings..."
    bash "$DOTFILES_DIR/aerospace/configure.sh"
  fi

  # Configure git to use repo's hooks directory (for pre-commit linting)
  log "Setting up git hooks..."
  if [[ -d "$DOTFILES_DIR/hooks" ]]; then
    git -C "$DOTFILES_DIR" config core.hooksPath hooks
    log "Git hooks configured to use $DOTFILES_DIR/hooks"
  else
    warn "Hooks directory not found at $DOTFILES_DIR/hooks - skipping git hooks setup"
  fi

  # Apply fast-syntax-highlighting theme (one-time)
  local fsh_theme="$HOME/.config/fsh/tokyonight.ini"
  if [[ -f "$fsh_theme" ]]; then
    if command -v zsh &> /dev/null; then
      # Try via interactive zsh so plugin-provided fast-theme is available
      if ! zsh -i -c "fast-theme \"$fsh_theme\"" &> /dev/null; then
        # Fallback: call the script directly if present
        local fsh_bin="$HOME/.zsh-custom/plugins/fast-syntax-highlighting/bin/fast-theme"
        if [[ -x "$fsh_bin" ]]; then
          "$fsh_bin" "$fsh_theme" || warn "Failed to apply fast-syntax-highlighting theme via direct script"
        else
          warn "fast-theme command not found; open a new zsh and run: fast-theme \"$fsh_theme\""
        fi
      else
        log "Applied fast-syntax-highlighting theme"
      fi
    fi
  else
    warn "fast-syntax-highlighting theme not found at $fsh_theme"
  fi

  log "✅ All done! Your development environment is ready."
}

main "$@"
