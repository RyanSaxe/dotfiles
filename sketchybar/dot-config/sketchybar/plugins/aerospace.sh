#!/usr/bin/env zsh
# Aerospace workspace indicator plugin
# Updates workspace highlighting when the workspace changes or colors update.
#
# States:
# - Active (focused): accent color (follows the mascot)
# - Inactive: dim
#
# Agent attention is NOT here: it has its own "A" letter (plugins/agent.sh)
# rather than borrowing the code workspace's highlight, which conflated
# "an agent needs you" with "this is where your terminal lives".

source "$HOME/.config/sketchybar/colors.sh"

# SketchyBar passes FOCUSED_WORKSPACE on aerospace_workspace_change.
# Cache it so color/bell refreshes don't need to shell out to AeroSpace.
FOCUSED_CACHE="$HOME/.cache/aerospace-focused-workspace"
if [[ -n "${FOCUSED_WORKSPACE:-}" ]]; then
  FOCUSED="$FOCUSED_WORKSPACE"
  mkdir -p "${FOCUSED_CACHE:h}" 2>/dev/null || true
  print -r -- "$FOCUSED" >|"$FOCUSED_CACHE"
elif [[ -r "$FOCUSED_CACHE" ]]; then
  FOCUSED=$(<"$FOCUSED_CACHE")
else
  FOCUSED=$(aerospace list-workspaces --focused 2>/dev/null)
fi

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
