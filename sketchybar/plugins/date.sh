#!/usr/bin/env zsh
# Date plugin - displays current date with calendar icon
# Uses prominent Pokemon color (purple accent)

source "$HOME/.config/sketchybar/colors.sh"

DATE=$(date '+%a %b %d')

sketchybar --set "$NAME" \
  icon.color="$ACCENT_COLOR" \
  label="$DATE" \
  label.color="$ACCENT_COLOR"
