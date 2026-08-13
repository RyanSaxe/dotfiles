#!/bin/sh
# Runs from the status line every status-interval. When the rendered color
# file changes, re-source it so the whole server recolors. Pull-based on
# purpose: it runs inside tmux's own context, so no external process needs
# the right PATH or permissions to recolor tmux — theme switches converge
# within one status-interval on any machine.
set -eu

colors="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/generated/tmux-colors.conf"
[ -f "$colors" ] || exit 0

# stat -f is BSD/macOS, stat -c is GNU/Linux.
mtime="$(stat -f %m "$colors" 2>/dev/null || stat -c %Y "$colors" 2>/dev/null)"
seen="$(tmux show -gqv @theme_colors_mtime)"

if [ "$mtime" != "$seen" ]; then
  tmux source-file -q "$colors"
  tmux set -g @theme_colors_mtime "$mtime"
fi
