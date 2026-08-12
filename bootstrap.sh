#!/bin/sh
# Install system packages, enable the commit gate, and print install steps.
# Run from the repo root. Safe to re-run; every step is idempotent.
set -eu

case "$(uname -s)" in
Darwin)
  command -v brew >/dev/null 2>&1 || {
    echo "error: homebrew is required first: https://brew.sh" >&2
    exit 1
  }
  brew install stow git gh git-delta uv
  ;;
Linux)
  sudo apt-get update
  sudo apt-get install -y stow git gh git-delta curl
  # uv is not packaged in apt; use the official installer.
  command -v uv >/dev/null 2>&1 || curl -LsSf https://astral.sh/uv/install.sh | sh
  ;;
*)
  echo "error: unsupported OS: $(uname -s)" >&2
  exit 1
  ;;
esac

# The commit gate (see README: Development).
uv tool install --quiet prek
git config core.hooksPath .githooks

# Quoted delimiter: the $(...) below are printed literally, not expanded.
cat <<'EOF'

bootstrap complete. install dotfiles with:

  stow -t ~ $(cat tiers/core.txt)    # every machine
  stow -t ~ $(cat tiers/mac.txt)     # macOS only
  stow -t ~ $(cat tiers/agents.txt)  # AI agent harness (optional)
EOF
