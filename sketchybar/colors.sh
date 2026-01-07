#!/usr/bin/env zsh
# Sketchybar color definitions
# Sources pokemon colors from ~/.cache/pokemon-colors.env

# -----------------------------------------------------------------------------
# Load Pokemon Colors
# -----------------------------------------------------------------------------
if [[ -f "$HOME/.cache/pokemon-colors.env" ]]; then
  source "$HOME/.cache/pokemon-colors.env"
fi

# Pokemon colors with TokyoNight fallbacks
POKEMON_DIM="${POKEMON_COLOR_DIM:-#565f89}"
POKEMON_PROMINENT="${POKEMON_COLOR_PROMINENT:-#7aa2f7}"
POKEMON_BRIGHT="${POKEMON_COLOR_BRIGHT:-#ff9e64}"

# -----------------------------------------------------------------------------
# Color Format Conversion
# -----------------------------------------------------------------------------
hex_to_argb() {
  local hex="${1#\#}"
  echo "0xff$hex"
}

hex_to_argb_alpha() {
  local hex="${1#\#}"
  local alpha="$2"
  echo "0x${alpha}${hex}"
}

# -----------------------------------------------------------------------------
# TokyoNight Theme Colors
# -----------------------------------------------------------------------------
export BAR_COLOR="0xff16161e"
export ITEM_BG="0x00000000"
export LABEL_COLOR="0xffc0caf5"
export FG_GUTTER="0xff3b4261"

export GREEN="0xff9ece6a"
export RED="0xfff7768e"
export YELLOW="0xffe0af68"
export CYAN="0xff7dcfff"
export PURPLE="0xffbb9af7"

# -----------------------------------------------------------------------------
# Pokemon-Derived Colors
# -----------------------------------------------------------------------------
export ICON_COLOR=$(hex_to_argb "$POKEMON_DIM")

export WORKSPACE_ACTIVE_FG=$(hex_to_argb "$POKEMON_PROMINENT")
export WORKSPACE_ACTIVE_BG=$(hex_to_argb_alpha "${POKEMON_PROMINENT#\#}" "33")
export WORKSPACE_INACTIVE_FG=$(hex_to_argb "$POKEMON_DIM")
export WORKSPACE_INACTIVE_BG="0x00000000"
export WORKSPACE_BORDER=$(hex_to_argb "#404040")

export TIME_NORMAL=$(hex_to_argb "$POKEMON_DIM")
export TIME_HIGHLIGHT=$(hex_to_argb "$POKEMON_BRIGHT")

export ACCENT_COLOR=$(hex_to_argb "$POKEMON_PROMINENT")
export ALERT_COLOR=$(hex_to_argb "$POKEMON_BRIGHT")
