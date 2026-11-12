#!/usr/bin/env zsh
# The "A" agent-attention letter: a pseudo-workspace indicator sitting
# after the real workspace letters, lit from the statuses agents report to
# Rex. cmd-alt-a walks through the agents, the one that wants you first.
#
# `ws attention --watch` publishes the level:
# - waiting: an agent is blocked on you, or failed
# - none:    dim, like an unfocused workspace, and still a keybind reminder
#
# A finished agent leaves it dim, since Rex can't say when you've seen one.

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
