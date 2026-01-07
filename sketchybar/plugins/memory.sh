#!/usr/bin/env zsh
# Memory usage plugin

source "$HOME/.config/sketchybar/colors.sh"

# Get memory pressure percentage (more reliable on macOS)
MEM_PRESSURE=$(memory_pressure 2> /dev/null | grep "System-wide memory free percentage" | awk '{print int($5)}')

if [[ -n "$MEM_PRESSURE" ]]; then
  MEM=$((100 - MEM_PRESSURE))
else
  MEM="--"
fi

if [[ "$MEM" == "--" ]]; then
  COLOR="$ICON_COLOR"
elif [[ "$MEM" -gt 80 ]]; then
  COLOR="$RED"
elif [[ "$MEM" -gt 60 ]]; then
  COLOR="$YELLOW"
else
  COLOR="$ICON_COLOR"
fi

sketchybar --set "$NAME" label="${MEM}%" icon.color="$COLOR"
