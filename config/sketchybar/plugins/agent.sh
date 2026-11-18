#!/usr/bin/env zsh
# The "A" agent-attention letter: a pseudo-workspace indicator sitting
# after the real workspace letters, lit while an agent in Rex or tmux needs
# you. cmd-alt-a walks through those agents, failed first, then blocked,
# then done, and within each the one that has waited longest first.
#
# `ws attention --watch` publishes the level:
# - failed:  a failed agent needs you
# - waiting: a blocked agent needs you, or a tmux agent rang its bell, which
#   doesn't say why
# - done:    only agents that finished since you last looked at them need you
# - none:    dim, like an unfocused workspace, and still a keybind reminder

source "$HOME/.config/sketchybar/colors.sh"

ATTENTION_FILE="$HOME/.local/state/ws/agent-attention"
ATTENTION="none"
[[ -r "$ATTENTION_FILE" ]] && ATTENTION=$(<"$ATTENTION_FILE")

case "$ATTENTION" in
failed)
  sketchybar --set "$NAME" \
    icon.color="$AGENT_FAILED_FG" \
    background.color="$AGENT_FAILED_BG" \
    background.drawing=on
  ;;
waiting)
  sketchybar --set "$NAME" \
    icon.color="$AGENT_WAITING_FG" \
    background.color="$AGENT_WAITING_BG" \
    background.drawing=on
  ;;
done)
  sketchybar --set "$NAME" \
    icon.color="$AGENT_DONE_FG" \
    background.color="$AGENT_DONE_BG" \
    background.drawing=on
  ;;
*)
  sketchybar --set "$NAME" \
    icon.color="$WORKSPACE_INACTIVE_FG" \
    background.color="$WORKSPACE_INACTIVE_BG" \
    background.drawing=off
  ;;
esac
