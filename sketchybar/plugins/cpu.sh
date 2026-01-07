#!/usr/bin/env zsh
# CPU usage plugin

source "$HOME/.config/sketchybar/colors.sh"

# Get CPU usage using top
CPU=$(top -l 1 -n 0 2> /dev/null | grep "CPU usage" | awk '{print int($3)}')

if [[ -z "$CPU" ]]; then
  CPU="--"
  COLOR="$ICON_COLOR"
else
  if [[ "$CPU" -gt 80 ]]; then
    COLOR="$RED"
  elif [[ "$CPU" -gt 50 ]]; then
    COLOR="$YELLOW"
  else
    COLOR="$ICON_COLOR"
  fi
fi

sketchybar --set "$NAME" label="${CPU}%" icon.color="$COLOR"
