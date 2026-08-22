#!/usr/bin/env zsh
# The "A" agent-attention letter: a pseudo-workspace indicator sitting
# after the real workspace letters, lit from the rail daemon's attention
# state. It is the visible half of cmd-alt-a — when it lights up, that
# chord takes you to the agent that wants you.
#
# States mirror the rail's own semantics (waiting outranks done):
# - waiting: an agent is blocked on you
# - done:    an agent finished and has not been visited
# - none:    dim, like an unfocused workspace — still a keybind reminder
#
# Attention is cleared by visiting the agent's window, so this goes dark
# on its own; nothing here acknowledges anything.

source "$HOME/.config/sketchybar/colors.sh"

ATTENTION_FILE="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/rail/attention"
ATTENTION="none"
[[ -r "$ATTENTION_FILE" ]] && ATTENTION=$(<"$ATTENTION_FILE")

case "$ATTENTION" in
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
