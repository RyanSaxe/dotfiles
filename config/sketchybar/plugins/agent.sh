#!/usr/bin/env zsh
# The "A" agent-attention letter: a pseudo-workspace indicator sitting
# after the real workspace letters, lit while an agent in Rex or tmux needs
# you. cmd-alt-a walks through those agents, the one that has waited longest
# first.
#
# `ws attention --watch` publishes the level:
# - waiting: an agent needs you: it failed, waits on you, or finished since
#   you last looked at it
# - none:    dim, like an unfocused workspace, and still a keybind reminder

source "$HOME/.config/sketchybar/colors.sh"

ATTENTION_FILE="$HOME/.local/state/ws/agent-attention"
ATTENTION="none"
[[ -r "$ATTENTION_FILE" ]] && ATTENTION=$(<"$ATTENTION_FILE")

case "$ATTENTION" in
waiting)
  sketchybar --set "$NAME" \
    icon.color="$AGENT_WAITING_FG" \
    background.color="$AGENT_WAITING_BG" \
    background.drawing=on
  ;;
*)
  sketchybar --set "$NAME" \
    icon.color="$WORKSPACE_INACTIVE_FG" \
    background.color="$WORKSPACE_INACTIVE_BG" \
    background.drawing=off
  ;;
esac
