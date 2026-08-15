#!/bin/sh
# Auto content-pane separators: a window's crust hairlines show only
# while it holds two or more CONTENT panes (@rail excluded). Hooks call
# this on pane create/exit (instant); the rail daemon reconciles every
# tick (inevitable). The border styles in tmux.conf read #{@wborders}
# at draw time.

window="$1"
[ -n "$window" ] || exit 0

n="$(tmux list-panes -t "$window" -F '#{@rail}' 2>/dev/null | grep -cv 1)"
n="${n:-0}"

if [ "$n" -ge 2 ]; then
  tmux set -w -t "$window" @wborders 1 2>/dev/null
else
  tmux set -w -t "$window" -u @wborders 2>/dev/null
fi

exit 0
