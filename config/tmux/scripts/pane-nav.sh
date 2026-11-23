#!/bin/sh
# alt+h / alt+l: navigate back and forward through pane focus history across
# splits, windows and sessions.
#
# History (@TMUX_CURR_PANE, @TMUX_HIST_BACK, @TMUX_HIST_FWD) is maintained by
# the in-server focus hooks in tmux.conf. One jump raises up to three focus
# events (switch-client, select-window, select-pane) whose partial views would
# each shift history, so the jump holds @TMUX_HIST_LOCK, which the hooks skip,
# and writes the updated stacks itself.

direction="${1:-back}"
max_hist=50

case "$direction" in
back | forward) ;;
*) exit 2 ;;
esac

state="$(tmux display-message -p '#{pane_id}|#{pane_floating}|#{@TMUX_CURR_PANE}|#{@TMUX_HIST_BACK}|#{@TMUX_HIST_FWD}' 2>/dev/null)"
origin="${state%%|*}"
rest="${state#*|}"
origin_floating="${rest%%|*}"
rest="${rest#*|}"
curr="${rest%%|*}"
rest="${rest#*|}"
back_stack="${rest%%|*}"
fwd_stack="${rest#*|}"

if [ "$direction" = "back" ]; then
  src="$back_stack"
  dst="$fwd_stack"
else
  src="$fwd_stack"
  dst="$back_stack"
fi

[ -n "$src" ] || exit 0

# Trim a space-separated pane list to at most $max_hist entries.
cap_stack() {
  out=""
  count=0
  for item in $1; do
    count=$((count + 1))
    [ "$count" -gt "$max_hist" ] && break
    out="${out:+$out }$item"
  done
  printf '%s' "$out"
}

# Pop until a live, non-floating pane other than the current one is found.
# Closed panes are dropped silently.
target=""
target_session=""
remaining=""
found=0
for entry in $src; do
  if [ "$found" = 1 ]; then
    remaining="${remaining:+$remaining }$entry"
    continue
  fi
  if [ "$origin_floating" != 1 ] && [ "$entry" = "$origin" ]; then
    continue
  fi
  case "$entry" in
  %*) info="$(tmux display-message -p -t "$entry" '#{pane_id}|#{pane_floating}|#{session_name}' 2>/dev/null)" ;;
  *) info="" ;;
  esac
  id="${info%%|*}"
  rest="${info#*|}"
  floating="${rest%%|*}"
  session="${rest#*|}"
  if [ -n "$info" ] && [ "$id" = "$entry" ] && [ "$floating" != 1 ] && [ -n "$session" ]; then
    target="$entry"
    target_session="$session"
    found=1
  fi
done

if [ "$found" != 1 ]; then
  if [ "$direction" = "back" ]; then
    tmux set-option -gu @TMUX_HIST_BACK
  else
    tmux set-option -gu @TMUX_HIST_FWD
  fi
  exit 0
fi

# A crash between taking and releasing the lock would leave the hooks skipping
# every focus event; the trap releases it on any exit path.
trap 'tmux set-option -gu @TMUX_HIST_LOCK' EXIT

# One chained invocation: the lock lands in the same command queue slot as
# the moves, so no hook can observe the jump unlocked. tmux stops a chain at
# its first failing command, so a pane that vanished since the check above
# cannot become a wrong-session window hop.
tmux set-option -g @TMUX_HIST_LOCK 1 \; \
  switch-client -t "=$target_session" \; \
  select-window -t "$target" \; \
  select-pane -t "$target" || exit 0

push=""
if [ "$origin_floating" != 1 ] && [ -n "$origin" ] && [ "$origin" != "$target" ]; then
  push="$origin"
elif [ -n "$curr" ] && [ "$curr" != "$target" ]; then
  push="$curr"
fi

if [ -n "$push" ]; then
  head="${dst%% *}"
  if [ "$head" != "$push" ]; then
    dst="$push${dst:+ $dst}"
  fi
fi

new_src="$(cap_stack "$remaining")"
new_dst="$(cap_stack "$dst")"

if [ "$direction" = "back" ]; then
  new_back="$new_src"
  new_fwd="$new_dst"
else
  new_back="$new_dst"
  new_fwd="$new_src"
fi

tmux set-option -g @TMUX_HIST_BACK "$new_back" \; \
  set-option -g @TMUX_HIST_FWD "$new_fwd" \; \
  set-option -g @TMUX_CURR_PANE "$target" \; \
  set-option -gu @TMUX_HIST_LOCK
