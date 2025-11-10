#!/usr/bin/env bash
# Returns pokemon colors for tmux theming
# Usage: pokemon-color.sh <type>
# Types: dim, prominent, bright
#
# Priority:
# 1. Override from config file (if set)
# 2. Pokemon color from cache (if exists)
# 3. TokyoNight default

set -euo pipefail

# Color type argument (dim, prominent, or bright)
color_type="${1:-}"

# Validate argument
if [[ -z "$color_type" ]]; then
  echo "Usage: pokemon-color.sh <dim|prominent|bright>" >&2
  exit 1
fi

# Config and cache files
config_file="$HOME/.config/tmux/pokemon-colors.conf"
cache_file="$HOME/.cache/pokemon-colors.env"

# Get TokyoNight default for this color type
case "$color_type" in
  dim)
    default_color="#565f89"  # gray
    ;;
  prominent)
    default_color="#7aa2f7"  # blue
    ;;
  bright)
    default_color="#ff9e64"  # orange
    ;;
  *)
    echo "Invalid color type: $color_type" >&2
    echo "Valid types: dim, prominent, bright" >&2
    exit 1
    ;;
esac

# Initialize result with default
result="$default_color"

# Step 1: Load pokemon color from cache if it exists
if [[ -f "$cache_file" ]]; then
  # shellcheck disable=SC1090
  source "$cache_file"

  case "$color_type" in
    dim)
      result="${POKEMON_COLOR_DIM:-$default_color}"
      ;;
    prominent)
      result="${POKEMON_COLOR_PROMINENT:-$default_color}"
      ;;
    bright)
      result="${POKEMON_COLOR_BRIGHT:-$default_color}"
      ;;
  esac
fi

# Step 2: Check for override in config (takes precedence over pokemon color)
if [[ -f "$config_file" ]]; then
  # shellcheck disable=SC1090
  source "$config_file"

  case "$color_type" in
    dim)
      if [[ -n "${POKEMON_COLOR_DIM_OVERRIDE:-}" ]]; then
        result="$POKEMON_COLOR_DIM_OVERRIDE"
      fi
      ;;
    prominent)
      if [[ -n "${POKEMON_COLOR_PROMINENT_OVERRIDE:-}" ]]; then
        result="$POKEMON_COLOR_PROMINENT_OVERRIDE"
      fi
      ;;
    bright)
      if [[ -n "${POKEMON_COLOR_BRIGHT_OVERRIDE:-}" ]]; then
        result="$POKEMON_COLOR_BRIGHT_OVERRIDE"
      fi
      ;;
  esac
fi

echo "$result"
