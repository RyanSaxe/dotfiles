#!/usr/bin/env zsh
# Aerospace workspace indicator plugin
# Updates workspace highlighting when workspace changes, colors update, or tmux bell fires
#
# States:
# - Active (focused): accent color (follows the pokemon)
# - Bell (code workspace with tmux bell): notify color (follows the pokemon)
# - Inactive: dim

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

# Check for tmux bell state from cache file (persists across events)
# Written by tmux/scripts/bell-cache-updater.sh
BELL_CACHE="$HOME/.cache/tmux-bell-active"
if [[ -f "$BELL_CACHE" ]]; then
  BELL_ACTIVE=$(cat "$BELL_CACHE" 2>/dev/null)
else
  BELL_ACTIVE="0"
fi

# Determine state: bell > active > inactive
if [[ "$WORKSPACE" == "code" && "$BELL_ACTIVE" == "1" ]]; then
  # Bell state: code workspace has pending notification (shows even when focused)
  sketchybar --set "$NAME" \
    icon.color="$BELL_FG" \
    background.color="$BELL_BG" \
    background.drawing=on
elif [[ "$WORKSPACE" == "$FOCUSED" ]]; then
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
