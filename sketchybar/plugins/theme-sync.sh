#!/usr/bin/env zsh
# Runs off its own item's update_freq. sketchybar has no "just re-source and
# everything restyles" primitive like tmux's @variables, so when the
# rendered colors file changes mtime, this recolors the bar chrome directly
# and fires mascot_colors_changed for items that don't refresh often enough
# on their own (date, workspaces) — mirrors tmux's theme-sync.sh convergence.
source "$HOME/.config/sketchybar/colors.sh"

COLORS_FILE="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/generated/sketchybar-colors.sh"
CACHE="$HOME/.cache/sketchybar-colors-mtime"

[[ -f "$COLORS_FILE" ]] || exit 0

MTIME=$(stat -f %m "$COLORS_FILE" 2>/dev/null || stat -c %Y "$COLORS_FILE" 2>/dev/null)
SEEN=""
[[ -f "$CACHE" ]] && SEEN=$(<"$CACHE")

# A theme_changed event is authoritative even when only the inner layer
# changed and the outer colors file kept the same mtime.
if [[ "$SENDER" != "theme_changed" && "$MTIME" == "$SEEN" ]]; then
  exit 0
fi

sketchybar --bar color="$BAR_COLOR" border_color="$BORDER_COLOR" \
  --default icon.color="$ICON_COLOR" label.color="$LABEL_COLOR" \
  --trigger mascot_colors_changed

mkdir -p "${CACHE:h}"
print -r -- "$MTIME" >|"$CACHE"
