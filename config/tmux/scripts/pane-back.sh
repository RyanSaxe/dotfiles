#!/bin/sh
# alt+L: jump back to the previous pane, across sessions.
#
# History (@TMUX_CURR_PANE/@TMUX_PREV_PANE) is maintained by the in-server
# focus hooks in tmux.conf. One jump raises up to three focus events
# (switch-client, select-window, select-pane) whose partial views would
# each shift history, so the jump holds @TMUX_HIST_LOCK, which the hooks
# skip, and makes one authoritative write itself, below.

state="$(tmux display-message -p '#{pane_id}|#{pane_floating}|#{@TMUX_PREV_PANE}' 2>/dev/null)"
origin="${state%%|*}"
rest="${state#*|}"
origin_floating="${rest%%|*}"
prev="${rest#*|}"
[ -n "$prev" ] || exit 0

# Pane ids are stable, so a previous pane that no longer resolves is really
# gone, not renumbered. No hook can reap dead panes from history
# (pane-exited formats the SURVIVING pane, never the dying one), so stale
# entries are dropped here, silently: a keystroke that found nothing is not
# worth a modal. A floating pane is a display surface, never a destination.
case "$prev" in
%*) info="$(tmux display-message -p -t "$prev" '#{pane_id}|#{pane_floating}|#{session_name}' 2>/dev/null)" ;;
*) info="" ;;
esac
id="${info%%|*}"
rest="${info#*|}"
floating="${rest%%|*}"
session="${rest#*|}"
if [ -z "$info" ] || [ "$id" != "$prev" ] || [ "$floating" = 1 ] || [ -z "$session" ]; then
  tmux set-option -gu @TMUX_PREV_PANE
  exit 0
fi

# A crash between taking and releasing the lock would leave the hooks
# skipping every focus event; the trap releases it on any exit path.
trap 'tmux set-option -gu @TMUX_HIST_LOCK' EXIT

# One chained invocation: the lock lands in the same command queue slot as
# the moves, so no hook can observe the jump unlocked. tmux stops a chain at
# its first failing command, so a pane that vanished since the check above
# cannot become a wrong-session window hop.
tmux set-option -g @TMUX_HIST_LOCK 1 \; \
  switch-client -t "=$session" \; \
  select-window -t "$prev" \; \
  select-pane -t "$prev" || exit 0

# The hooks skipped every event above, so CURR is written here. A
# recordable origin (a non-floating pane other than the target) becomes
# PREV directly. Otherwise PREV takes the pre-jump CURR only if the jump
# really moved, in-server, with the same format the hooks use.
if [ "$origin_floating" != 1 ] && [ -n "$origin" ] && [ "$origin" != "$prev" ]; then
  tmux set-option -g @TMUX_PREV_PANE "$origin" \; \
    set-option -g @TMUX_CURR_PANE "$prev" \; \
    set-option -gu @TMUX_HIST_LOCK
else
  tmux set-option -gF @TMUX_PREV_PANE \
    "#{?#{==:#{@TMUX_CURR_PANE},$prev},#{@TMUX_PREV_PANE},#{@TMUX_CURR_PANE}}" \; \
    set-option -g @TMUX_CURR_PANE "$prev" \; \
    set-option -gu @TMUX_HIST_LOCK
fi
