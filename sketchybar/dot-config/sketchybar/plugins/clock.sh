#!/usr/bin/env zsh
# Clock plugin - time only with meeting reminder highlighting.
# SACRED: minutes 00, 29, 30, 59 highlight so a meeting never gets missed —
# 1 minute before and right at the start of every half hour. Preserve this
# exactly; ported from v1's date.sh/clock.sh unchanged except the color
# source.
#
# The highlight is peach, not the mascot accent. It means check whether
# something is starting, and that has to read the same way whichever mascot
# is worn — a warning that changes colour with the wallpaper is decoration.

source "$HOME/.config/sketchybar/colors.sh"

TIME=$(date '+%H:%M')
MINUTE=$(date '+%M')

if [[ "$MINUTE" == "00" || "$MINUTE" == "29" || "$MINUTE" == "30" || "$MINUTE" == "59" ]]; then
  COLOR="$TIME_HIGHLIGHT"
else
  COLOR="$TIME_NORMAL"
fi

sketchybar --set "$NAME" \
  icon.color="$COLOR" \
  label="$TIME" \
  label.color="$COLOR"
