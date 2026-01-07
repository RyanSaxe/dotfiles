#!/usr/bin/env zsh
# Battery plugin

source "$HOME/.config/sketchybar/colors.sh"

PERCENTAGE=$(pmset -g batt | grep -Eo "\d+%" | cut -d% -f1)
CHARGING=$(pmset -g batt | grep 'AC Power')

if [[ -z "$PERCENTAGE" ]]; then
  sketchybar --set "$NAME" drawing=off
  exit 0
fi

# Battery icon based on charge level
case "${PERCENTAGE}" in
  100) ICON="󰁹" ;;
  9[0-9]) ICON="󰂂" ;;
  8[0-9]) ICON="󰂁" ;;
  7[0-9]) ICON="󰂀" ;;
  6[0-9]) ICON="󰁿" ;;
  5[0-9]) ICON="󰁾" ;;
  4[0-9]) ICON="󰁽" ;;
  3[0-9]) ICON="󰁼" ;;
  2[0-9]) ICON="󰁻" ;;
  1[0-9]) ICON="󰁺" ;;
  *) ICON="󰂃" ;;
esac

if [[ -n "$CHARGING" ]]; then
  ICON="󰂄"
fi

if [[ "$PERCENTAGE" -lt 25 ]]; then
  ICON_CLR="$RED"
  LABEL_CLR="$RED"
elif [[ "$PERCENTAGE" -lt 50 ]]; then
  ICON_CLR="$YELLOW"
  LABEL_CLR="$YELLOW"
else
  ICON_CLR="$ICON_COLOR"
  LABEL_CLR="$LABEL_COLOR"
fi

sketchybar --set "$NAME" \
  icon="$ICON" \
  icon.color="$ICON_CLR" \
  label="${PERCENTAGE}%" \
  label.color="$LABEL_CLR" \
  drawing=on
