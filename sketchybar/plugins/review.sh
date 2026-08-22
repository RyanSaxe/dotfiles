#!/usr/bin/env zsh
# The "R" review letter: the same shape as the agent "A", answering the
# neighbouring question — is there GitHub work waiting on me. It is the
# visible half of cmd-alt-r, which lands on the terminal and opens the
# Reviews dashboard.
#
# States mirror the dashboard's own hues:
# - ci:     a check is failing on your own pull request
# - review: a comment, review request or issue is waiting
# - none:   dim, like an unfocused workspace — still a keybind reminder
#
# The level is published by the rail daemon (see notifications.ts). This
# reads a one-word file rather than the observer's state, because a menu bar
# parsing a locked JSON document on a timer is how an indicator becomes load.

source "$HOME/.config/sketchybar/colors.sh"

ATTENTION_FILE="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/rail/review-attention"
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
