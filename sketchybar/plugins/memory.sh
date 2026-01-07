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
  ICON_CLR="$ICON_COLOR"
  LABEL_CLR="$LABEL_COLOR"
elif [[ "$MEM" -gt 75 ]]; then
  ICON_CLR="$RED"
  LABEL_CLR="$RED"
elif [[ "$MEM" -gt 50 ]]; then
  ICON_CLR="$YELLOW"
  LABEL_CLR="$YELLOW"
else
  ICON_CLR="$ICON_COLOR"
  LABEL_CLR="$LABEL_COLOR"
fi

sketchybar --set "$NAME" label="${MEM}%" icon.color="$ICON_CLR" label.color="$LABEL_CLR"
