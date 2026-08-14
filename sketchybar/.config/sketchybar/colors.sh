#!/usr/bin/env zsh
# Colors are never hardcoded here — they're rendered by `theme` from tokens
# (see theme/.config/theme/templates/sketchybar-colors.sh.tmpl). Every
# plugin and sketchybarrc itself source this file to pick them up.
source "${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/generated/sketchybar-colors.sh"
