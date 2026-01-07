#!/usr/bin/env zsh
# Aerospace workspace indicator plugin
# Updates workspace highlighting when workspace changes or colors update

source "$HOME/.config/sketchybar/colors.sh"

# Get current focused workspace from aerospace
FOCUSED=$(aerospace list-workspaces --focused 2> /dev/null)

# Extract workspace name from item name (space.email -> email)
WORKSPACE="${NAME#space.}"

if [[ "$WORKSPACE" == "$FOCUSED" ]]; then
  # Active workspace: prominent color with subtle background
  sketchybar --set "$NAME" \
    icon.color="$WORKSPACE_ACTIVE_FG" \
    background.color="$WORKSPACE_ACTIVE_BG" \
    background.drawing=on
else
  # Inactive workspace: dim color, transparent background
  sketchybar --set "$NAME" \
    icon.color="$WORKSPACE_INACTIVE_FG" \
    background.color="$WORKSPACE_INACTIVE_BG" \
    background.drawing=off
fi
