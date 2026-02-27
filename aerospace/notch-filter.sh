#!/usr/bin/env bash
# Git smudge/clean filter for aerospace.toml
# Adjusts outer.top gap for MacBook notch on a per-machine basis.
#
# Smudge (checkout): detects notch, rewrites outer.top for per-monitor gaps
# Clean (staging): normalizes outer.top back to the repo default (52)

set -euo pipefail

ACTION="${1:-}"
CACHE_FILE="$HOME/.cache/aerospace-notch-inset"

case "$ACTION" in
  smudge)
    # Read cached notch inset (populated by install.sh or aerospace/configure.sh)
    INSET=$(cat "$CACHE_FILE" 2> /dev/null || echo "0")
    if [[ "$INSET" -gt 0 ]]; then
      BUILTIN_TOP=$((52 - INSET))
      [[ "$BUILTIN_TOP" -lt 0 ]] && BUILTIN_TOP=0
      sed "s/^outer\.top = .*/outer.top = [{ monitor.'built-in' = $BUILTIN_TOP }, 52]/"
    else
      cat # No notch, pass through unchanged
    fi
    ;;
  clean)
    # Always normalize to the repo default
    sed "s/^outer\.top = .*/outer.top = 52/"
    ;;
  *)
    cat # Unknown action, pass through
    ;;
esac
