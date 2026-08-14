#!/usr/bin/env zsh
# Date plugin - displays current date with calendar icon
# Uses the accent color, which follows the pokemon

source "$HOME/.config/sketchybar/colors.sh"

DATE=$(date '+%a %b %d')

sketchybar --set "$NAME" \
  icon.color="$ACCENT_COLOR" \
  label="$DATE" \
  label.color="$ACCENT_COLOR"
