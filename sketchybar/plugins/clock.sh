#!/usr/bin/env zsh
# Clock plugin - time only with meeting reminder highlighting
# Minutes 00, 29, 30, 59 = orange (meeting reminders)

source "$HOME/.config/sketchybar/colors.sh"

TIME=$(date '+%H:%M')
MINUTE=$(date '+%M')

# Highlight at meeting reminder times (start/end of hour, half hour)
if [[ "$MINUTE" == "00" || "$MINUTE" == "29" || "$MINUTE" == "30" || "$MINUTE" == "59" ]]; then
  COLOR="$TIME_HIGHLIGHT"
else
  COLOR="$WORKSPACE_ACTIVE_FG"
fi

sketchybar --set "$NAME" \
  icon.color="$COLOR" \
  label="$TIME" \
  label.color="$COLOR"
