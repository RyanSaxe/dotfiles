#!/usr/bin/env zsh
# The "R" review letter: the same shape as the agent "A", answering the
# neighbouring question: is there GitHub work waiting on me. Alt-R in Rex
# or tmux opens the Reviews popup.
#
# `ws attention --watch` asks GitHub every 5 minutes and publishes:
# - ci:     a failing check on one of your pull requests needs you
# - review: anything else in Reviews' Needs you tab
# - none:   dim, like an unfocused workspace, and still a keybind reminder
#
# This reads the one-word file it writes, so the bar never waits on GitHub.

source "$HOME/.config/sketchybar/colors.sh"

ATTENTION_FILE="$HOME/.local/state/ws/review-attention"
ATTENTION="none"
[[ -r "$ATTENTION_FILE" ]] && ATTENTION=$(<"$ATTENTION_FILE")

case "$ATTENTION" in
ci)
  sketchybar --set "$NAME" \
    icon.color="$REVIEW_CI_FG" \
    background.color="$REVIEW_CI_BG" \
    background.drawing=on
  ;;
review)
  sketchybar --set "$NAME" \
    icon.color="$REVIEW_PENDING_FG" \
    background.color="$REVIEW_PENDING_BG" \
    background.drawing=on
  ;;
*)
  sketchybar --set "$NAME" \
    icon.color="$WORKSPACE_INACTIVE_FG" \
    background.color="$WORKSPACE_INACTIVE_BG" \
    background.drawing=off
  ;;
esac
