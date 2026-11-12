#!/usr/bin/env zsh
# Aerospace workspace indicators: one repaint of every letter per event.
#
# Runs for the workspace_sync item on aerospace_workspace_change. Which
# workspace is focused is asked of AeroSpace
# itself rather than read from the event, so a script that starts late
# paints the current truth, not the state its event described. One process
# per letter, each deciding for itself with no ordering between them, would
# leave two letters lit whenever two events land close together.
#
# Active: accent color. Inactive: dim.
# Agent attention is NOT here: it has its own "A" letter (plugins/agent.sh)
# rather than borrowing the code workspace's highlight.

source "$HOME/.config/sketchybar/colors.sh"
source "$HOME/.config/sketchybar/workspaces.sh"

focused="$(aerospace list-workspaces --focused 2>/dev/null)"

args=()
for workspace in "${WORKSPACES[@]}"; do
  if [[ "$workspace" == "$focused" ]]; then
    args+=(
      --set "space.$workspace"
      icon.color="$WORKSPACE_ACTIVE_FG"
      background.color="$WORKSPACE_ACTIVE_BG"
      background.drawing=on
    )
  else
    args+=(
      --set "space.$workspace"
      icon.color="$WORKSPACE_INACTIVE_FG"
      background.color="$WORKSPACE_INACTIVE_BG"
      background.drawing=off
    )
  fi
done
sketchybar "${args[@]}"
