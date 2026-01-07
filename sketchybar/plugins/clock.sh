#!/usr/bin/env zsh
# Clock plugin with date and meeting reminder coloring
# Minutes 00, 29, 30, 59 = orange (meeting reminders)

source "$HOME/.config/sketchybar/colors.sh"

# Get current date and time
DATE=$(date '+%a %b %d')
TIME=$(date '+%H:%M')
MINUTE=$(date '+%M')

# Determine color based on minute (meeting reminder logic)
if [[ "$MINUTE" == "00" || "$MINUTE" == "29" || "$MINUTE" == "30" || "$MINUTE" == "59" ]]; then
  TIME_COLOR="$TIME_HIGHLIGHT"
else
  TIME_COLOR="$TIME_NORMAL"
fi

sketchybar --set "$NAME" label="$DATE  $TIME" label.color="$TIME_COLOR"
