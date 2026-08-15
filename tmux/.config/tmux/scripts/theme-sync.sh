#!/bin/sh
# Invoked by the rail daemon when the generated color files change (the
# status line is off; the rail carries the chrome). When the rendered color
# file changes, re-source it so the whole server recolors. mtime-guarded so
# redundant invocations cost one stat, not a re-source.
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
