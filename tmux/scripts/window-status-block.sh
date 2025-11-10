#!/usr/bin/env bash
set -euo pipefail

# Build complete formatted window status blocks (active and inactive)
# This ensures consistent color usage within each format string
# Usage: window-status-block.sh <active|inactive>

mode="${1:-inactive}"

# Get pokemon colors from cached tmux variables (set by color-cache-updater.sh)
# This is MUCH faster than calling pokemon-color.sh on every window render
dim_color=$(tmux show -gv @pokemon_dim 2>/dev/null || echo "#565f89")
prominent_color=$(tmux show -gv @pokemon_prominent 2>/dev/null || echo "#7aa2f7")
bright_color=$(tmux show -gv @pokemon_bright 2>/dev/null || echo "#ff9e64")

# Get static colors and separators from tmux
bg_color=$(tmux show -gv @tokyonight_bg 2>/dev/null || echo "#1a1b26")
fg_gutter=$(tmux show -gv @tokyonight_fg_gutter 2>/dev/null || echo "#3b4261")
left_rounded=$(tmux show -gv @left_rounded 2>/dev/null || echo "")
right_rounded=$(tmux show -gv @right_rounded 2>/dev/null || echo "")

if [[ "$mode" == "active" ]]; then
  # Active window: pokemon prominent for number, pokemon bright for separator, pokemon prominent for window name
  echo "#[fg=${prominent_color},bg=${bg_color}]${left_rounded}#[fg=${bg_color},bg=${prominent_color},bold] #I #[fg=${bright_color},bg=${prominent_color}]#[fg=${prominent_color},bg=${fg_gutter},bold] #W #[fg=${fg_gutter},bg=${bg_color}]${right_rounded}"
else
  # Inactive window: pokemon dim for all elements
  echo "#[fg=${dim_color},bg=${bg_color}]${left_rounded}#[fg=${bg_color},bg=${dim_color},bold] #I #[fg=${dim_color},bg=${fg_gutter}]#[fg=${bg_color},bg=${dim_color}] #W #[fg=${dim_color},bg=${bg_color}]${right_rounded}"
fi
