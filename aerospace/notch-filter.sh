#!/bin/sh
# Git smudge/clean filter for aerospace.toml: outer.top per machine.
#
# The built-in display reserves the camera-housing rows, so its top gap
# must shrink by the measured inset to keep windows level with external
# monitors. smudge (checkout) writes the per-monitor value; clean
# (staging) normalizes back to the repo default so the machine-specific
# number never lands in history.
#
# The 52 below is the shared default, derived from sketchybar's geometry
# by the rule in aerospace.toml's [gaps] comment. It appears three times
# here and once there; all four move together or one machine ends up
# with the wrong gap.
set -eu

ACTION="${1:-}"
CACHE_FILE="$HOME/.cache/aerospace-notch-inset"

case "$ACTION" in
smudge)
  # Inset cache is written by configure.sh (run from install.sh).
  INSET="$(cat "$CACHE_FILE" 2>/dev/null || echo 0)"
  case "$INSET" in
  '' | *[!0-9]*) INSET=0 ;;
  esac
  if [ "$INSET" -gt 0 ]; then
    BUILTIN_TOP=$((52 - INSET))
    [ "$BUILTIN_TOP" -lt 0 ] && BUILTIN_TOP=0
    sed "s/^outer\.top = .*/outer.top = [{ monitor.'built-in' = $BUILTIN_TOP }, 52]/"
  else
    cat # No notch: pass through unchanged.
  fi
  ;;
clean)
  sed "s/^outer\.top = .*/outer.top = 52/"
  ;;
*)
  cat # Unknown action: pass through.
  ;;
esac
