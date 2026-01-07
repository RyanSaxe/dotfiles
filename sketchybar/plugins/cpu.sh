#!/usr/bin/env zsh
# CPU usage plugin

source "$HOME/.config/sketchybar/colors.sh"

# Get CPU usage using top
CPU=$(top -l 1 -n 0 2> /dev/null | grep "CPU usage" | awk '{print int($3)}')

if [[ -z "$CPU" ]]; then
  CPU="--"
  ICON_CLR="$ICON_COLOR"
  LABEL_CLR="$LABEL_COLOR"
else
  if [[ "$CPU" -gt 75 ]]; then
    ICON_CLR="$RED"
    LABEL_CLR="$RED"
  elif [[ "$CPU" -gt 50 ]]; then
    ICON_CLR="$YELLOW"
    LABEL_CLR="$YELLOW"
  else
    ICON_CLR="$ICON_COLOR"
    LABEL_CLR="$LABEL_COLOR"
  fi
fi

sketchybar --set "$NAME" label="${CPU}%" icon.color="$ICON_CLR" label.color="$LABEL_CLR"
