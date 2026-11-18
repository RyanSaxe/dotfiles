#!/bin/sh
# Records an agent's status on the tmux pane it runs in, where ws reads it.
# Claude Code runs it from its hooks as
#
#   tmux-agent-status.sh APP STATE
#
# with APP the agent's name as Rex reports it, such as claude-code, and STATE
# working, blocked, done or error. Without a STATE it clears the pane's
# status, as when the session ends. The pane also keeps the time and the process that ran
# the hook, which is the agent, so that ws counts the status only while that
# agent runs. In Rex, where TMUX_PANE is unset, the agent reports its own
# status, so this does nothing.
#
# The agent waits for each hook, so this makes one tmux call. A hook must
# never fail the agent, so this prints nothing and always exits 0.

[ -n "$TMUX_PANE" ] || exit 0
if [ -n "$2" ]; then
  tmux set-option -p -t "$TMUX_PANE" @ws_status "$2" \; \
    set-option -p -t "$TMUX_PANE" @ws_app "$1" \; \
    set-option -p -t "$TMUX_PANE" @ws_pid "$PPID" \; \
    set-option -p -t "$TMUX_PANE" @ws_since "$(date +%s)"
else
  tmux set-option -pu -t "$TMUX_PANE" @ws_status \; \
    set-option -pu -t "$TMUX_PANE" @ws_app \; \
    set-option -pu -t "$TMUX_PANE" @ws_pid \; \
    set-option -pu -t "$TMUX_PANE" @ws_since
fi >/dev/null 2>&1
exit 0
