#!/bin/sh
# One-command setup. Run from the repo root on a fresh machine or an old one:
#
#   ./install.sh              interactive: choose tiers, then install
#   ./install.sh core         non-interactive: install the named tiers
#   ./install.sh core mac
#   ./install.sh links        symlinks only: redeploy every tier (or the
#                             named ones), no package installs
#   ./install.sh upgrade      upgrade every package manager, print a
#                             before/after summary; pin bumps (rail
#                             lockfile, prek revs) are left uncommitted
#
# Re-running updates: packages upgrade to current versions and symlinks are
# redeployed. Every step is idempotent.
set -eu

OS="$(uname -s)"
# Linux installers put user tools in ~/.local/bin. Add it before any package
# or deploy step so this process can use tools that it installs there.
if [ "$OS" = Linux ]; then
  case ":${PATH:-}:" in
  *":$HOME/.local/bin:"*) ;;
  *)
    PATH="$HOME/.local/bin${PATH:+:$PATH}"
    export PATH
    ;;
  esac
fi
# Physical (-P) so paths through symlinked components (/var -> /private/var
# on macOS) can't split into logical/physical mixtures: dotbot computes
# relative links physically, so a logical base or target home would produce
# links that climb to the wrong root and a clean pass that misses them.
REPO_ROOT="$(CDPATH='' cd -P "$(dirname "$0")" && pwd -P)"
AI_HARNESS_SOURCE="$REPO_ROOT/ai-harness"
# No arguments and a real terminal means a human is driving: the tier and
# agent pickers prompt. A scripted run takes the defaults instead.
INTERACTIVE=0
if [ "$#" -eq 0 ] && [ -t 0 ]; then INTERACTIVE=1; fi

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
# System packages per tier and OS, named per package manager. The symlink
# deployment map for each tier lives in tiers/<tier>.yaml.

# One inventory per package manager. POSIX sh has no arrays: these are
# space-separated words, expanded unquoted on purpose (hence the shellcheck
# disables at each use).
CORE_BREW_FORMULAS='git gh git-delta uv starship fzf tmux node bat fd ripgrep rsync neovim lua-language-server stylua jq'
# fd-find: apt names the binary fdfind; aliases.zsh renames it back.
CORE_APT_PACKAGES='git gh git-delta curl zsh fzf tmux nodejs npm bat fd-find ripgrep rsync jq'
MAC_BREW_FORMULAS='sketchybar'
MAC_BREW_CASKS='ghostty aerospace font-jetbrains-mono-nerd-font karabiner-elements'
# byor's rule engine. Not in Debian or Ubuntu, so Linux takes the npm build
# into ~/.local like the agent CLIs do.
EXTRAS_BREW_FORMULAS='ast-grep'
EXTRAS_NPM_PACKAGES='@ast-grep/cli'
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

# The rail TUI and account observer (tuis/rail) run via tsx from their own
# node_modules.
install_rail() {
  (cd "$RAIL_DIR" && npm install --no-fund --no-audit --silent)
}

install_attention_agent() {
  [ "$OS" = Darwin ] || return 0
  # Scratch-home health checks and explicit package-only runs must never touch
  # the real user's launchd domain.
  [ -z "${DOTFILES_TARGET:-}" ] || return 0

  launch_agents="$HOME/Library/LaunchAgents"
  plist="$launch_agents/com.ryansaxe.dotfiles.attention.plist"
  state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/attention"
  mkdir -p "$launch_agents" "$state_dir"
  sed \
    -e "s|__ATTENTION_BIN__|$HOME/.local/bin/attention|g" \
    -e "s|__ATTENTION_LOG__|$state_dir/launchd.log|g" \
    launchd/com.ryansaxe.dotfiles.attention.plist >"$plist"

  domain="gui/$(id -u)"
  launchctl bootout "$domain/com.ryansaxe.dotfiles.attention" 2>/dev/null || true
  launchctl bootstrap "$domain" "$plist"
  launchctl kickstart -k "$domain/com.ryansaxe.dotfiles.attention"
}

install_starship() {
  # starship has no self-update; rerunning the official installer is also
  # the upgrade path.
  curl -sS https://starship.rs/install.sh | sh -s -- -y
}

# Tap and trust in one motion. Homebrew 6 ignores third-party taps until
# `brew trust` runs -- a fresh machine taps successfully and then finds
# no formulae. Older brews have no trust command; the gate keeps them
# working. Every future tap goes through here, not bare `brew tap`.
brew_tap_trusted() {
  brew tap "$1"
  if brew trust --help >/dev/null 2>&1; then
    brew trust "$1"
  fi
}

install_workmux() {
  # workmux drives every worktree/window in this setup and its config ships
  # in the core tier, so the binary belongs here too. Homebrew serves it
  # from the author's tap; Linux gets the release tarball (a bare binary),
  # which is also the upgrade path.
  case "$OS" in
  Darwin)
    brew_tap_trusted raine/workmux
    brew_install workmux
    ;;
  *)
    case "$(uname -m)" in
    aarch64 | arm64) workmux_arch=arm64 ;;
    *) workmux_arch=amd64 ;;
    esac
    mkdir -p "$HOME/.local/bin"
    curl -fsSL "https://github.com/raine/workmux/releases/latest/download/workmux-linux-$workmux_arch.tar.gz" |
      tar -xz -C "$HOME/.local/bin"
    ;;
  esac
}

# Agent CLIs, by the name their binary answers to. brew casks on macOS (what
# this machine already runs); npm elsewhere, into ~/.local so no sudo and no
# root-owned files — the bootstrap and zshenv put that bin dir on PATH.
AGENT_CLIS='claude codex copilot'

install_agent_cli() {
  case "$1" in
  claude) agent_cask='claude-code@latest' agent_pkg='@anthropic-ai/claude-code' ;;
  codex) agent_cask='codex' agent_pkg='@openai/codex' ;;
  copilot) agent_cask='copilot-cli' agent_pkg='@github/copilot' ;;
  *)
    echo "error: unknown agent CLI: $1" >&2
    return 1
    ;;
  esac
  command -v "$1" >/dev/null 2>&1 && return 0
  case "$OS" in
  # Casks error on reinstall, unlike formulas.
  Darwin) brew list --cask "$agent_cask" >/dev/null 2>&1 || brew install --cask "$agent_cask" ;;
  *) npm install -g --prefix "$HOME/.local" "$agent_pkg" ;;
  esac
}

# workmux discovers agents by their config directories, so the CLIs must land
# first. Workmux setup is deliberately deferred until every selected tier has
# installed its harness links: setup --hooks/--skills is non-interactive and
# can then configure the complete filesystem state in one pass.
setup_agents() {
  [ "${AGENT_CLIS_SETUP_DONE:-0}" = 1 ] && return 0
  chosen=''
  for agent in $AGENT_CLIS; do
    if [ "$INTERACTIVE" = 1 ]; then
      ask "install the $agent CLI?" && chosen="$chosen $agent"
    else
      chosen="$chosen $agent"
    fi
  done
  for agent in $chosen; do
    install_agent_cli "$agent"
  done
  AGENT_CLIS_SETUP_DONE=1
}

# AI harness files span plugin roots, native user directories, and Codex's
# admin directory. The tier maps intentionally do not cover it: every
# link below points back to the authored tree, while application state stays
# in the harness home.
link_owned() {
  source="$1"
  target="$2"
  target_dir="${target%/*}"
  mkdir -p "$target_dir"
  if [ -L "$target" ]; then
    [ "$(readlink "$target")" = "$source" ] && return 0
    rm "$target"
  elif [ -e "$target" ]; then
    echo "error: refusing to replace existing file: $target" >&2
    echo "move it aside, then re-run the installer" >&2
    return 1
  fi
  ln -s "$source" "$target"
}

link_system_owned() {
  source="$1"
  target="$2"
  if sudo test -L "$target"; then
    [ "$(sudo readlink "$target")" = "$source" ] && return 0
    sudo rm "$target"
  elif sudo test -e "$target"; then
    echo "error: refusing to replace existing file: $target" >&2
    echo "move it aside, then re-run the installer" >&2
    return 1
  fi
  sudo mkdir -p "${target%/*}"
  sudo ln -s "$source" "$target"
}

remove_system_link_matching() {
  target="$1"
  suffix="$2"
  if sudo test -L "$target"; then
    link="$(sudo readlink "$target")"
    case "$link" in *"$suffix") sudo rm "$target" ;; esac
  fi
}

install_ai_harness() {
  # Both the core and agents tiers want the harness, and the default run
  # installs both — same reason setup_agents guards itself just above.
  [ "${AI_HARNESS_SETUP_DONE:-0}" = 1 ] && return 0
  [ -d "$AI_HARNESS_SOURCE" ] || {
    echo "error: missing $AI_HARNESS_SOURCE" >&2
    return 1
  }

  # One stable root lets the shell wrappers pass the live repository to the
  # Claude and Copilot plugin loaders without copying or generating files.
  link_owned "$AI_HARNESS_SOURCE" "$HOME/.config/ai-harness"

  link_owned "$AI_HARNESS_SOURCE/AGENTS.md" "$HOME/.claude/CLAUDE.md"
  link_owned "$AI_HARNESS_SOURCE/statusline.js" "$HOME/.claude/statusline.js"
  link_owned "$AI_HARNESS_SOURCE/references" "$HOME/.claude/references"

  link_owned "$AI_HARNESS_SOURCE/AGENTS.md" "$HOME/.copilot/copilot-instructions.md"
  link_owned "$AI_HARNESS_SOURCE/copilot/settings.json" "$HOME/.copilot/settings.json"
  link_owned "$AI_HARNESS_SOURCE/statusline.js" "$HOME/.copilot/statusline.js"
  link_owned "$AI_HARNESS_SOURCE/references" "$HOME/.copilot/references"

  link_owned "$AI_HARNESS_SOURCE/AGENTS.md" "$HOME/.codex/AGENTS.md"
  link_owned "$AI_HARNESS_SOURCE/references" "$HOME/.codex/references"
  remove_system_link_matching "/etc/codex/config.toml" "/ai-harness/codex/config.toml"
  link_system_owned "$AI_HARNESS_SOURCE/codex/managed_config.toml" "/etc/codex/managed_config.toml"
  link_system_owned "$AI_HARNESS_SOURCE/skills" "/etc/codex/skills"

  # ~/.codex/config.toml is Codex's own mutable state and the installer does
  # not edit it. Portable defaults live in managed config now, so a top-level
  # `model` or `model_reasoning_effort` left in the user file will shadow
  # them — but that file also holds settings nobody here put there, and
  # rewriting it in place would be this script quietly editing personal
  # configuration on every run. Removing those keys is a one-time cleanup for
  # whoever carried the old shape forward, not an install step.
  mkdir -p "$HOME/.codex"
  AI_HARNESS_SETUP_DONE=1
}

install_neovim_linux() {
  # apt's neovim lags far behind the nvim config's 0.12 floor; the official
  # tarball into ~/.local is both the install and the upgrade path.
  # lua-language-server and stylua stay mac-only for now: prek vendors its
  # own stylua, and lua editing happens on the mac.
  case "$(uname -m)" in
  aarch64 | arm64) nvim_arch=arm64 ;;
  *) nvim_arch=x86_64 ;;
  esac
  mkdir -p "$HOME/.local"
  curl -fsSL "https://github.com/neovim/neovim/releases/latest/download/nvim-linux-$nvim_arch.tar.gz" |
    tar -xz -C "$HOME/.local" --strip-components=1
}

# Secrets and per-machine ids live in an untracked .env at the repo root,
# loaded by zsh (env_init) and by the rail launcher. It can never be
# installed for you — but a fresh box silently losing phone notifications
# because nobody knew the file existed is worse than being nagged.
#
# One "NAME description" per line; the description is what the prompt shows.
REQUIRED_ENV_VARS='AGENT_NOTIFICATION_ID ntfy.sh topic id for agent and review phone notifications'

# Same file, but no nagging: these are genuinely optional. They live here
# rather than in a tracked config because their values name private
# repositories, and .env is the one place that never reaches git.
OPTIONAL_ENV_VARS='ATTENTION_WATCH space-separated owner/name repositories to hear about even when you are not involved'

ensure_env_file() {
  if [ ! -f .env ]; then
    {
      echo "# Untracked machine-local secrets, loaded by zsh and the rail launcher."
      echo "$REQUIRED_ENV_VARS" | while read -r name description; do
        [ -n "$name" ] || continue
        echo "# $description"
        echo "$name="
      done
      echo "$OPTIONAL_ENV_VARS" | while read -r name description; do
        [ -n "$name" ] || continue
        echo
        echo "# Optional. $description"
        echo "# $name=\"owner/name other/name\""
      done
    } >.env
  fi
  echo "$REQUIRED_ENV_VARS" | while read -r name description; do
    [ -n "$name" ] || continue
    grep -q "^$name=." .env && continue
    printf '\033[1;31mACTION REQUIRED\033[0m set %s in %s/.env — %s\n' \
      "$name" "$PWD" "$description" >&2
  done
}

# ------------------------------------------------------------------- vault
# Notes live in a Markdown vault, which is a repository of its own and never
# part of the dotfiles. This is the only place that offers to get one onto the
# machine, and it never contains a personal repository URL. zsh/zshenv is
# where the path is declared; the default repeats it for a first run, before
# any shell has sourced it.
VAULT_DIR="${VAULT_DIR:-$HOME/generic/vault}"
export VAULT_DIR

setup_vault() {
  vault_bin="$HOME/.local/bin/vault"
  # The CLI deploys with the core tier; with no CLI there is nothing to ask.
  # Scratch-home checks must never create a vault in the real home either.
  [ -x "$vault_bin" ] || return 0
  [ -z "${DOTFILES_TARGET:-}" ] || return 0

  command -v rg >/dev/null 2>&1 ||
    echo "warning: ripgrep not found; note search, backlinks, and tags return nothing" >&2
  command -v uv >/dev/null 2>&1 ||
    echo "warning: uv not found; the vault CLI cannot run" >&2

  if [ ! -d "$VAULT_DIR" ]; then
    # A scripted run does nothing here: installation must never block on a
    # prompt or create a vault nobody asked for. Neovim's health check
    # reports the missing vault later instead.
    [ "$INTERACTIVE" = 1 ] || return 0
    echo "==> vault"
    if ask "do you already have a vault repository?"; then
      printf 'owner/repo or git URL: '
      read -r vault_repo
      case "$vault_repo" in
      '')
        echo "no repository given; skipping the vault" >&2
        return 0
        ;;
      *://* | *@*:*) vault_url="$vault_repo" ;;
      *) vault_url="https://github.com/$vault_repo" ;;
      esac
      # A newly created repository is empty. Cloning one succeeds and leaves
      # a working tree with no commits, which is the expected starting state.
      git clone "$vault_url" "$VAULT_DIR" || return 1
      # Adds every missing part of the contract, changes nothing that exists.
      "$vault_bin" init --in-place "$VAULT_DIR" || return 1
    else
      "$vault_bin" init "$VAULT_DIR" || return 1
    fi
  fi
  # The report is the point: a failing check is actionable, not fatal.
  "$vault_bin" check || true
}

# render-markdown renders LaTeX through the first converter it finds,
# preferring utftex and falling back to latex2text. utftex is a brew
# formula with no apt equivalent; pylatexenc ships latex2text and
# installs the same way on every OS, so one mechanism covers both rather
# than a mac-only formula plus a Linux fallback. nvim/lua/markdown/health.lua
# fails the checkhealth report without one of them.
install_latex_converter() {
  uv tool install --quiet pylatexenc
}

install_tier_packages() {
  case "$1:$OS" in
  core:Darwin)
    # shellcheck disable=SC2086
    brew_install $CORE_BREW_FORMULAS
    install_workmux
    setup_agents
    install_ai_harness
    ensure_zsh_login_shell
    install_zsh_plugins
    install_rail
    install_latex_converter
    ;;
  core:Linux)
    # shellcheck disable=SC2086
    apt_install $CORE_APT_PACKAGES
    # uv, starship, and a current neovim are not packaged (or too old) in
    # apt; use the official installers.
    command -v uv >/dev/null 2>&1 || curl -LsSf https://astral.sh/uv/install.sh | sh
    command -v starship >/dev/null 2>&1 || install_starship
    command -v nvim >/dev/null 2>&1 || install_neovim_linux
    install_workmux
    setup_agents
    install_ai_harness
    ensure_zsh_login_shell
    install_zsh_plugins
    install_rail
    install_latex_converter
    ;;
  agents:Darwin | agents:Linux)
    # The agents tier can be installed on an existing machine without the
    # core tier, but its final setup pass still needs the Workmux binary.
    command -v workmux >/dev/null 2>&1 || install_workmux
    setup_agents
    install_ai_harness
    ;;
  mac:Darwin)
    # sketchybar itself is mac-only; the plugins under sketchybar/ shell out
    # to macOS-only tools (pmset, ipconfig) regardless. It lives in the
    # felixkratz tap.
    brew_tap_trusted felixkratz/formulae
    # shellcheck disable=SC2086
    brew_install $MAC_BREW_FORMULAS
    # aerospace is a cask in nikitabobko's tap; install skips when present
    # (casks error on reinstall, unlike formulas).
    brew_tap_trusted nikitabobko/tap
    for cask in $MAC_BREW_CASKS; do
      brew list --cask "$cask" >/dev/null 2>&1 || brew install --cask "$cask"
    done
    # Per-machine notch compensation for aerospace's top gap.
    ./aerospace/configure.sh
    ;;
  extras:Darwin | extras:Linux)
    # Optional tooling. Nothing else depends on this tier, and a machine that
    # declines it should look as though the tier did not exist — which is why
    # deploy_tier refuses to link byor's config unless byor is actually here.
    if [ "$OS" = Darwin ]; then
      # shellcheck disable=SC2086
      brew_install $EXTRAS_BREW_FORMULAS
    else
      # shellcheck disable=SC2086
      command -v ast-grep >/dev/null 2>&1 ||
        npm install -g --prefix "$HOME/.local" $EXTRAS_NPM_PACKAGES
    fi
    uv tool install --quiet byor
    # byor owns its agent wiring and its shipped rule packages. Both commands
    # are idempotent, so reproducing them beats the repo carrying copies that
    # would drift out of step with the tool.
    byor install >/dev/null 2>&1 || true
    byor package install style >/dev/null 2>&1 || true
    ;;
  *)
    echo "error: unknown tier for $OS: $1" >&2
    exit 1
    ;;
  esac
}

# ------------------------------------------------------------------ deploy
# Symlinks are deployed by dotbot from one explicit map per tier
# (tiers/<tier>.yaml): whole config directories linked as directories, per-file
# links only where a program writes into the directory, plus native cleanup of
# links whose source file was renamed or deleted. dotbot runs through uvx, so
# the deployment tool itself needs no install step anywhere uv exists.

# Source directories the tier maps deploy from. Deployment reads the
# filesystem, not the git index, so junk inside these trees matters twice
# over now that they are linked whole: gitignored files are declared junk and
# deleted, and untracked files refuse to deploy. Note what a directory link
# changes here — a file in one of these trees is live the moment it is
# written, so the refusal below gates the deploy, not the file's visibility.
DEPLOY_SOURCE_DIRS='git zsh theme nvim tmux workmux tuis/rail/bin clis bat ghostty sketchybar aerospace byor'

ensure_uv() {
  command -v uvx >/dev/null 2>&1 && return 0
  case "$OS" in
  Darwin)
    if command -v brew >/dev/null 2>&1; then
      brew_install uv
    else
      echo "error: uv is required to deploy symlinks (brew install uv)" >&2
      exit 1
    fi
    ;;
  *) curl -LsSf https://astral.sh/uv/install.sh | sh ;;
  esac
}

clean_deploy_sources() {
  # shellcheck disable=SC2086
  git clean -qfdX -- $DEPLOY_SOURCE_DIRS
  # shellcheck disable=SC2086
  find $DEPLOY_SOURCE_DIRS -mindepth 1 -type d -empty -delete 2>/dev/null || true
  # shellcheck disable=SC2086
  untracked="$(git ls-files --others --exclude-standard -- $DEPLOY_SOURCE_DIRS)"
  if [ -n "$untracked" ]; then
    echo "error: untracked files would deploy into HOME:" >&2
    printf '%s\n' "$untracked" | sed 's/^/  /' >&2
    echo "commit or remove them, then re-run" >&2
    exit 1
  fi
}

# Config directories the map once filled with per-file links and now links
# whole. An install from before that change has a real directory sitting where
# the symlink belongs, and dotbot will not replace a directory it did not
# create — so clear it here first.
#
# Only when every entry inside is a link or a directory, though. A regular
# file is either something the owner put there or a program writing where the
# map says nothing writes; both are worth stopping for, and neither is worth
# deleting on the way past. Doing this rather than dotbot's `force` matters
# for exactly that reason: `force` is an unconditional rmtree.
LEGACY_CORE_LINK_DIRS='.config/zsh .config/git .config/theme .config/nvim .config/tmux .config/vault/templates'
LEGACY_MAC_LINK_DIRS='.config/sketchybar .config/aerospace'

migrate_link_dirs() {
  # Same resolution as deploy_tier: DOTFILES_TARGET redirects scratch-home
  # checks, and physical so a symlinked /var cannot split the comparison.
  migrate_home="$(cd -P "${DOTFILES_TARGET:-$HOME}" && pwd -P)"
  legacy_dirs=''
  for tier in "$@"; do
    case "$tier:$OS" in
    core:*) legacy_dirs="$legacy_dirs $LEGACY_CORE_LINK_DIRS" ;;
    mac:Darwin) legacy_dirs="$legacy_dirs $LEGACY_MAC_LINK_DIRS" ;;
    esac
  done
  for rel in $legacy_dirs; do
    dir="$migrate_home/$rel"
    # A link is already converted; a missing directory is a fresh machine.
    { [ -d "$dir" ] && [ ! -L "$dir" ]; } || continue
    strays="$(find "$dir" ! -type d ! -type l)"
    if [ -n "$strays" ]; then
      echo "error: $dir holds files this deploy did not put there:" >&2
      printf '%s\n' "$strays" | sed 's/^/  /' >&2
      echo "the map links this directory whole now; move them aside, then re-run" >&2
      exit 1
    fi
    echo "converting $rel to a directory link"
    rm -rf "$dir"
  done
}

deploy_tier() {
  if [ "$1" = mac ] && [ "$OS" != Darwin ]; then
    echo "skipping mac tier: not macOS"
    return 0
  fi
  # Tiers with no symlinks to deploy have no tiers/<name>.yaml.
  [ -f "tiers/$1.yaml" ] || return 0
  echo "deploy: $1"
  # Physical for the same reason as REPO_ROOT above.
  deploy_home="$(cd -P "${DOTFILES_TARGET:-$HOME}" && pwd -P)"
  # DOTFILES_TARGET redirects the links (scratch-home checks); the uv cache
  # stays under the real home, pinned before HOME is overridden. The two
  # disabled warnings describe exactly that intent: the assignments exist
  # only for the dotbot process, and $HOME in the cache path is the outer one.
  # shellcheck disable=SC2097,SC2098
  UV_CACHE_DIR="${UV_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/uv}" \
    HOME="$deploy_home" \
    uvx --quiet dotbot -d "$REPO_ROOT" -c "tiers/$1.yaml"
}

install_tier() {
  if [ "$1" = mac ] && [ "$OS" != Darwin ]; then
    echo "skipping mac tier: not macOS"
    return 0
  fi
  install_tier_packages "$1"
  deploy_tier "$1"
}

# ----------------------------------------------------------------- upgrade
# `./install.sh upgrade` — bring every package manager current and print one
# before/after summary at the end instead of scrollback. Package-manager work
# only: no symlink deployment (install owns that). Pinned versions (rail's
# package-lock.json, prek hook revs) are bumped in the working tree but never
# committed here; the diff is the proposal.

# Append one summary section: "name old -> new" per changed package, from two
# "name version..." snapshots.
report_changes() {
  {
    echo "$1:"
    changes="$(awk '
      FILENAME == ARGV[1] { before[$1] = substr($0, length($1) + 2); next }
      {
        after = substr($0, length($1) + 2)
        old = ($1 in before) ? before[$1] : "(new)"
        if (old != after) print "  " $1 "  " old " -> " after
      }
    ' "$2" "$3")"
    echo "${changes:-  up to date}"
  } >>"$SUMMARY"
}

upgrade_brew() {
  echo "==> brew"
  brew update
  formulas="$CORE_BREW_FORMULAS"
  # Only mac-tier packages that are actually installed: upgrade must not
  # pull GUI apps onto a machine that chose core only.
  for formula in $MAC_BREW_FORMULAS; do
    if brew list --versions "$formula" >/dev/null 2>&1; then
      formulas="$formulas $formula"
    fi
  done
  # A formula missing from the snapshot (nonzero exit) is not fatal: the
  # brew_install below installs it and the summary reports it as (new).
  # shellcheck disable=SC2086
  brew list --versions $formulas >"$WORK/brew.before" || true
  # shellcheck disable=SC2086
  brew_install $formulas
  # shellcheck disable=SC2086
  brew list --versions $formulas >"$WORK/brew.after"
  report_changes brew "$WORK/brew.before" "$WORK/brew.after"

  for cask in $MAC_BREW_CASKS; do
    if brew list --cask --versions "$cask" >"$WORK/cask.before" 2>/dev/null; then
      brew upgrade --cask "$cask"
      brew list --cask --versions "$cask" >"$WORK/cask.after"
      report_changes "brew cask" "$WORK/cask.before" "$WORK/cask.after"
    fi
  done
}

upgrade_apt() {
  echo "==> apt"
  # shellcheck disable=SC2086
  dpkg-query -W -f='${Package} ${Version}\n' $CORE_APT_PACKAGES 2>/dev/null |
    sort >"$WORK/apt.before"
  # shellcheck disable=SC2086
  apt_install $CORE_APT_PACKAGES
  # shellcheck disable=SC2086
  dpkg-query -W -f='${Package} ${Version}\n' $CORE_APT_PACKAGES 2>/dev/null |
    sort >"$WORK/apt.after"
  report_changes apt "$WORK/apt.before" "$WORK/apt.after"

  # The apt path installs uv, starship, and neovim via their official
  # installers, so they upgrade outside apt too (brew owns them on macOS).
  echo "==> standalone installers"
  {
    uv --version
    starship --version | head -n 1
    nvim --version | head -n 1
    workmux --version
  } >"$WORK/installers.before"
  uv self update
  install_starship
  install_neovim_linux
  install_workmux
  {
    uv --version
    starship --version | head -n 1
    nvim --version | head -n 1
    workmux --version
  } >"$WORK/installers.after"
  report_changes installers "$WORK/installers.before" "$WORK/installers.after"
}

zsh_plugin_revs() {
  for plugin in $ZSH_PLUGINS; do
    dir="$HOME/.local/share/zsh/plugins/${plugin##*/}"
    if [ -d "$dir/.git" ]; then
      echo "${plugin##*/} $(git -C "$dir" rev-parse --short HEAD)"
    fi
  done
}

upgrade_zsh_plugins() {
  echo "==> zsh plugins"
  zsh_plugin_revs >"$WORK/plugins.before"
  install_zsh_plugins
  zsh_plugin_revs >"$WORK/plugins.after"
  report_changes "zsh plugins" "$WORK/plugins.before" "$WORK/plugins.after"
}

# Direct rail deps at their locked versions. package-lock.json is the pin:
# `npm update` bumps it here, install syncs other machines to it.
rail_dep_versions() {
  (cd "$RAIL_DIR" && node -e '
    const lock = require("./package-lock.json");
    const pkg = require("./package.json");
    const names = Object.keys({ ...pkg.dependencies, ...pkg.devDependencies });
    for (const name of names.sort())
      console.log(name, (lock.packages["node_modules/" + name] || {}).version);
  ')
}

upgrade_rail() {
  echo "==> npm ($RAIL_DIR)"
  rail_dep_versions >"$WORK/rail.before"
  (cd "$RAIL_DIR" && npm update --no-fund --no-audit --silent)
  rail_dep_versions >"$WORK/rail.after"
  report_changes "npm ($RAIL_DIR)" "$WORK/rail.before" "$WORK/rail.after"
  git diff --quiet -- "$RAIL_DIR/package-lock.json" ||
    echo "  pin bump: review 'git diff $RAIL_DIR/package-lock.json' and commit" >>"$SUMMARY"
}

upgrade_uv_tools() {
  echo "==> uv tools"
  # --all reaches every uv tool on the machine, not just what install.sh
  # installs (prek): personally installed tools drift too. Narrow to an
  # inventory if that ever surprises.
  # Entry-point lines in `uv tool list` start with "- "; drop them. PEP 723
  # scripts need no step here: uv re-resolves them on every run.
  uv tool list --color never | awk '$1 != "-" && NF == 2' >"$WORK/uv.before"
  uv tool upgrade --all
  uv tool list --color never | awk '$1 != "-" && NF == 2' >"$WORK/uv.after"
  report_changes "uv tools" "$WORK/uv.before" "$WORK/uv.after"
}

prek_hook_revs() {
  awk '
    $2 == "repo:" { repo = $3; sub(".*/", "", repo) }
    $1 == "rev:" { print repo, $2 }
  ' .pre-commit-config.yaml
}

upgrade_prek_hooks() {
  echo "==> prek hooks"
  prek_hook_revs >"$WORK/prek.before"
  prek autoupdate
  prek_hook_revs >"$WORK/prek.after"
  report_changes "prek hooks" "$WORK/prek.before" "$WORK/prek.after"
  git diff --quiet -- .pre-commit-config.yaml ||
    echo "  pin bump: review 'git diff .pre-commit-config.yaml' and commit" >>"$SUMMARY"
}

# Run one manager in a set -e subshell: its failure lands in the summary
# instead of killing the run, and the managers after it still execute. The
# subshell must be a plain statement — in an if/&& condition every shell
# keeps set -e inert even when the subshell re-enables it.
run_step() {
  step="$1"
  shift
  set +e
  (
    set -e
    "$@"
  )
  step_status=$?
  set -e
  if [ "$step_status" -ne 0 ]; then
    echo "$step: FAILED (see output above)" >>"$SUMMARY"
    UPGRADE_FAILED=1
  fi
}

run_upgrade() {
  WORK="$(mktemp -d)"
  SUMMARY="$WORK/summary"
  : >"$SUMMARY"
  # Print whatever the run collected before cleaning up, however it exits.
  trap '
    echo
    echo "==> upgrade summary"
    cat "$SUMMARY"
    rm -rf "$WORK"
  ' EXIT
  UPGRADE_FAILED=0

  case "$OS" in
  Darwin) run_step brew upgrade_brew ;;
  Linux) run_step apt upgrade_apt ;;
  esac
  run_step "zsh plugins" upgrade_zsh_plugins
  run_step "npm ($RAIL_DIR)" upgrade_rail
  run_step "uv tools" upgrade_uv_tools
  run_step "prek hooks" upgrade_prek_hooks

  exit "$UPGRADE_FAILED"
}

# -------------------------------------------------------------------- main
# `links` verb: symlinks and their cleanup only, no package-manager work.
# CI runs this same path against a scratch HOME.
if [ "${1:-}" = links ]; then
  shift
  [ "$#" -gt 0 ] || set -- core mac extras
  ensure_uv
  clean_deploy_sources
  migrate_link_dirs "$@"
  for tier in "$@"; do
    deploy_tier "$tier"
  done
  exit 0
fi

ensure_package_manager

if [ "${1:-}" = upgrade ]; then
  run_upgrade
fi

# No tiers on the command line: choose interactively. The core and agents tiers
# install the live harness links after the CLIs themselves are available.
if [ "$#" -eq 0 ]; then
  set -- core agents
  if [ "$OS" = Darwin ] && ask "install the mac tier (GUI apps)?"; then
    set -- "$@" mac
  fi
  if ask "install the extras tier (byor and its rule engine)?"; then
    set -- "$@" extras
  fi
fi

ensure_uv
# uv normally fetches a managed CPython on demand, but a fresh machine
# refused to install byor over a missing >=3.11 interpreter anyway.
# Guarantee one up front; idempotent and instant when already present.
uv python install
clean_deploy_sources
migrate_link_dirs "$@"

for tier in "$@"; do
  echo "==> $tier"
  install_tier "$tier"
done

# Workmux discovers agent configuration from the installed filesystem. Run its
# explicit, non-interactive setup only after all requested tiers have linked
# the harness files and the Workmux config. This makes both `./install.sh` and
# explicit tier invocations complete installs; neither requires a follow-up
# manual `workmux setup` command.
if [ "${AGENT_CLIS_SETUP_DONE:-0}" = 1 ]; then
  echo "==> workmux agent hooks and skills"
  workmux setup --hooks --skills
fi

# Render the theme so every consumer has colors from the first shell.
if [ -x "$HOME/.local/bin/theme" ]; then
  "$HOME/.local/bin/theme" apply ||
    echo "warning: theme apply failed; continuing without refreshed generated theme" >&2
fi

# Rebuild bat's theme cache now that `theme apply` has published the rendered
# inner theme; apt names the binary batcat (see zsh/aliases.zsh for the alias).
if command -v bat >/dev/null 2>&1; then
  bat cache --build
elif command -v batcat >/dev/null 2>&1; then
  batcat cache --build
fi

# Machine-local values nothing can install for you; warns loudly per gap.
ensure_env_file

# The vault is content rather than configuration, so it is offered rather
# than installed: a scripted run leaves the machine without one.
setup_vault || echo "warning: vault setup did not complete" >&2

# The account observer is independent of tmux and Neovim, but its user-level
# launchd job is installed alongside the core rail package on macOS. Install
# it after .env exists so the first RunAtLoad refresh sees the phone channel.
if [ "$OS" = Darwin ] && [ -z "${DOTFILES_TARGET:-}" ]; then
  for tier in "$@"; do
    [ "$tier" = core ] || continue
    install_attention_agent
    break
  done
fi

# The commit gate for working on this repo (see README: Development).
uv tool install --quiet prek
git config core.hooksPath .githooks

echo
echo "done. re-run any time to update."
