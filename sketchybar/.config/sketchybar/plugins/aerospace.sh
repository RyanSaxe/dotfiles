#!/usr/bin/env zsh
# Aerospace workspace indicator plugin
# Updates workspace highlighting when the workspace changes, colors update,
# or the rail daemon's agent attention state changes
#
# States:
# - Agent waiting (code workspace): status_waiting semantic color
# - Agent done (code workspace): status_done semantic color
# - Active (focused): accent color (follows the pokemon)
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

# Agent attention (waiting|done|none), written by the rail daemon whenever
# an unacked agent status changes. Visiting the agent's window clears it.
ATTENTION_FILE="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/rail/attention"
ATTENTION="none"
[[ -r "$ATTENTION_FILE" ]] && ATTENTION=$(<"$ATTENTION_FILE")

# Determine state: waiting > done > active > inactive (attention shows even
# when the code workspace is focused)
if [[ "$WORKSPACE" == "code" && "$ATTENTION" == "waiting" ]]; then
  sketchybar --set "$NAME" \
    icon.color="$AGENT_WAITING_FG" \
    background.color="$AGENT_WAITING_BG" \
    background.drawing=on
elif [[ "$WORKSPACE" == "code" && "$ATTENTION" == "done" ]]; then
  sketchybar --set "$NAME" \
    icon.color="$AGENT_DONE_FG" \
    background.color="$AGENT_DONE_BG" \
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
