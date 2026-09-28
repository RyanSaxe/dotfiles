#!/bin/sh
# Invoked by the rail daemon when the generated color files change (the
# status line is off; the rail carries the chrome). When the rendered color
# file changes, re-source it so the whole server recolors. stamp-guarded so
# redundant invocations cost one stat, not a re-source.
set -eu

colors="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/generated/tmux-colors.conf"
[ -f "$colors" ] || exit 0

# Inode+mtime, not mtime alone: the theme publisher replaces the file by
# mv (new inode) only when content changed, and whole-second mtimes make
# two flips inside one second look identical.
# stat -f is BSD/macOS, stat -c is GNU/Linux.
stamp="$(stat -f %i-%m "$colors" 2>/dev/null || stat -c %i-%Y "$colors" 2>/dev/null)"
seen="$(tmux show -gqv @theme_colors_stamp)"

if [ "$stamp" != "$seen" ]; then
  tmux source-file -q "$colors"
  tmux set -g @theme_colors_stamp "$stamp"
fi
