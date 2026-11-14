#!/usr/bin/env zsh
# The "T" task letter, after A and R: is a task in the vault due. Alt-T in
# Rex or tmux opens the Tasks popup.
#
# `ws attention --watch` rereads the vault every minute and publishes:
# - overdue:  an open task is past its date
# - today:    one is due today
# - tomorrow: one is due tomorrow
# - none:     dim, like an unfocused workspace, and still a keybind reminder

source "$HOME/.config/sketchybar/colors.sh"

ATTENTION_FILE="$HOME/.local/state/ws/task-attention"
ATTENTION="none"
[[ -r "$ATTENTION_FILE" ]] && ATTENTION=$(<"$ATTENTION_FILE")

case "$ATTENTION" in
overdue)
  sketchybar --set "$NAME" \
    icon.color="$TASK_OVERDUE_FG" \
    background.color="$TASK_OVERDUE_BG" \
    background.drawing=on
  ;;
today)
  sketchybar --set "$NAME" \
    icon.color="$TASK_TODAY_FG" \
    background.color="$TASK_TODAY_BG" \
    background.drawing=on
  ;;
tomorrow)
  sketchybar --set "$NAME" \
    icon.color="$TASK_TOMORROW_FG" \
    background.color="$TASK_TOMORROW_BG" \
    background.drawing=on
  ;;
*)
  sketchybar --set "$NAME" \
    icon.color="$WORKSPACE_INACTIVE_FG" \
    background.color="$WORKSPACE_INACTIVE_BG" \
    background.drawing=off
  ;;
esac
