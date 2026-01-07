#!/usr/bin/env bash
# Front app plugin - displays currently focused application icon and name
source "$CONFIG_DIR/colors.sh"

# Handle app switch or color change events
case "$SENDER" in
  front_app_switched)
    sketchybar --set "$NAME" label="$INFO" icon.background.image="app.$INFO"
    ;;
  pokemon_colors_changed)
    # Re-source colors and update label color
    source "$CONFIG_DIR/colors.sh"
    sketchybar --set "$NAME" label.color="$ACCENT_COLOR"
    ;;
esac
