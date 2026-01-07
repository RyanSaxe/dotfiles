#!/usr/bin/env zsh
# Date plugin - displays current date with calendar icon

source "$HOME/.config/sketchybar/colors.sh"

DATE=$(date '+%a %b %d')

sketchybar --set "$NAME" \
  icon.color="$ICON_COLOR" \
  label="$DATE" \
  label.color="$LABEL_COLOR"
