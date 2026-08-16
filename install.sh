#!/bin/sh
# One-command setup. Run from the repo root on a fresh machine or an old one:
#
#   ./install.sh              interactive: choose tiers, then install
#   ./install.sh core         non-interactive: install the named tiers
#   ./install.sh core mac
#   ./install.sh stow         symlinks only: restow every tier (or the
#                             named ones), no package installs
#   ./install.sh upgrade      upgrade every package manager, print a
#                             before/after summary; pin bumps (rail
#                             lockfile, prek revs) are left uncommitted
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
CORE_BREW_FORMULAS='stow git gh git-delta uv starship fzf tmux node bat neovim lua-language-server stylua'
# make: ensure_modern_stow builds stow from source on LTS boxes.
CORE_APT_PACKAGES='stow git gh git-delta curl zsh fzf tmux nodejs npm bat make'
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

install_starship() {
  # starship has no self-update; rerunning the official installer is also
  # the upgrade path.
  curl -sS https://starship.rs/install.sh | sh -s -- -y
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

# apt's stow on LTS is 2.3.x, which breaks on --dotfiles dot- directories
# (fixed in 2.4). Build the release tarball over it when too old.
ensure_modern_stow() {
  case "$(stow --version)" in
  *"version 2."[0-3].*) ;;
  *) return 0 ;;
  esac
  build="$(mktemp -d)"
  curl -fsSL https://ftp.gnu.org/gnu/stow/stow-2.4.1.tar.gz | tar -xz -C "$build"
  (cd "$build/stow-2.4.1" && ./configure && sudo make install) >/dev/null
  rm -rf "$build"
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
    ensure_modern_stow
    # uv, starship, and a current neovim are not packaged (or too old) in
    # apt; use the official installers.
    command -v uv >/dev/null 2>&1 || curl -LsSf https://astral.sh/uv/install.sh | sh
    command -v starship >/dev/null 2>&1 || install_starship
    command -v nvim >/dev/null 2>&1 || install_neovim_linux
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
    ./aerospace/dot-config/aerospace/configure.sh
    ;;
  *)
    echo "error: unknown tier for $OS: $1" >&2
    exit 1
    ;;
  esac
}

# Directories that receive generated files at runtime: theme publish_files
# copies the rendered bat theme and ghostty shaders into ~/.config, and uv
# installs tool shims into ~/.local/bin. Each must be a real directory
# before stow runs: stow folds a missing directory into a symlink to the
# package tree, and these writes would then land inside the repo. .stowrc's
# --no-folding also prevents folding, but only when stow reads it (cwd is
# the repo root and the file parses); the pre-create holds regardless.
RUNTIME_WRITE_DIRS='.config/bat/themes .config/ghostty/shaders .config/ghostty/themes .local/bin'

ensure_runtime_write_dirs() {
  for dir in $RUNTIME_WRITE_DIRS; do
    mkdir -p "${DOTFILES_TARGET:-$HOME}/$dir"
  done
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

  # Stow deploys the filesystem, not the git index, so anything loose inside
  # a package would symlink into HOME (bytecode caches once linked
  # ~/tests/__pycache__). Gitignored files are declared junk: delete them,
  # and the empty directory chains they leave. Untracked files may be
  # unfinished work: refuse, so nothing links silently and nothing of value
  # is deleted.
  git clean -qfdX -- "$1"
  find "$1" -mindepth 1 -type d -empty -delete
  untracked="$(git ls-files --others --exclude-standard -- "$1")"
  if [ -n "$untracked" ]; then
    echo "error: untracked files in package $1 would stow into HOME:" >&2
    printf '%s\n' "$untracked" | sed 's/^/  /' >&2
    echo "commit or remove them, then re-run" >&2
    exit 1
  fi

  # Manifest paths are target-side: stow --dotfiles links dot-* entries to
  # their dotted names, and the cleanup below must visit those links.
  # -type l: a symlink shipped in a package stows like a file.
  current="$(cd "$1" && find . \( -type f -o -type l \) | sed 's|/dot-|/.|g' | sort)"

  if [ -f "$manifest" ]; then
    printf '%s\n' "$current" | comm -23 "$manifest" - | while IFS= read -r gone; do
      link="$target/${gone#./}"
      # Only touch broken symlinks; a real file there is not ours to delete.
      if [ -L "$link" ] && [ ! -e "$link" ]; then
        rm "$link"
        echo "cleaned dangling link: $link"
      fi
      prune_empty_dirs "$target" "${gone#./}"
    done
  fi

  stow -R --dotfiles -t "$target" "$1"
  printf '%s\n' "$current" >"$manifest"
}

# --no-folding makes stow create REAL directories around its per-file links,
# so a removed file leaves its directory chain behind after the link is
# cleaned. rmdir only ever deletes empty dirs and stops at the first
# non-empty parent, inside the target.
prune_empty_dirs() {
  dir="${2%/*}"
  if [ "$dir" != "$2" ]; then
    (cd "$1" && rmdir -p "$dir") 2>/dev/null || true
  fi
}

# install_tier visits only packages a tier currently names, so a package
# dropped from every tier (or renamed) would keep its links and manifest
# forever. Unstow by manifest; every listed entry still a symlink is ours.
remove_stale_packages() {
  target="${DOTFILES_TARGET:-$HOME}"
  manifest_dir="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/manifest"
  for manifest in "$manifest_dir"/*.txt; do
    [ -f "$manifest" ] || continue
    pkg="${manifest##*/}"
    pkg="${pkg%.txt}"
    if grep -qx "$pkg" tiers/*.txt; then continue; fi
    echo "unstowing removed package: $pkg"
    while IFS= read -r entry; do
      link="$target/${entry#./}"
      if [ -L "$link" ]; then rm "$link"; fi
      prune_empty_dirs "$target" "${entry#./}"
    done <"$manifest"
    rm "$manifest"
  done
}

stow_tier() {
  if [ "$1" = mac ] && [ "$OS" != Darwin ]; then
    echo "skipping mac tier: not macOS"
    return 0
  fi
  # Tiers with no stow packages yet have no tiers/<name>.txt.
  [ -s "tiers/$1.txt" ] || return 0
  while IFS= read -r pkg; do
    [ -n "$pkg" ] || continue
    echo "stow: $pkg"
    stow_package "$pkg"
  done <"tiers/$1.txt"
}

install_tier() {
  if [ "$1" = mac ] && [ "$OS" != Darwin ]; then
    echo "skipping mac tier: not macOS"
    return 0
  fi
  install_tier_packages "$1"
  stow_tier "$1"
}

# ----------------------------------------------------------------- upgrade
# `./install.sh upgrade` — bring every package manager current and print one
# before/after summary at the end instead of scrollback. Package-manager work
# only: no stow, no symlinks (install owns those). Pinned versions (rail's
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
  } >"$WORK/installers.before"
  uv self update
  install_starship
  install_neovim_linux
  {
    uv --version
    starship --version | head -n 1
    nvim --version | head -n 1
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
# `stow` verb: symlinks and their cleanup only, no package-manager work.
# CI runs this same path against a scratch HOME.
if [ "${1:-}" = stow ]; then
  shift
  [ "$#" -gt 0 ] || set -- core mac
  if [ "$OS" = Linux ]; then ensure_modern_stow; fi
  ensure_runtime_write_dirs
  remove_stale_packages
  for tier in "$@"; do
    stow_tier "$tier"
  done
  exit 0
fi

ensure_package_manager

if [ "${1:-}" = upgrade ]; then
  run_upgrade
fi

# No tiers on the command line: choose interactively. (An agents tier —
# interactive AI-harness wiring — arrives with the ai-harness rebuild.)
if [ "$#" -eq 0 ]; then
  set -- core
  if [ "$OS" = Darwin ] && ask "install the mac tier (GUI apps)?"; then
    set -- "$@" mac
  fi
fi

ensure_runtime_write_dirs

# Before stowing: a renamed package's old links would conflict with its new
# name's stow run.
remove_stale_packages

for tier in "$@"; do
  echo "==> $tier"
  install_tier "$tier"
done

# Render the theme so every consumer has colors from the first shell.
if [ -x "$HOME/.local/bin/theme" ]; then
  "$HOME/.local/bin/theme" apply
fi

# Rebuild bat's theme cache now that `theme apply` has published the rendered
# inner theme; apt names the binary batcat (see zsh/aliases.zsh for the alias).
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
