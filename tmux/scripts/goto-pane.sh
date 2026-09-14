#!/bin/sh
# The ONE cross-session jump primitive: land on a pane and let the global
# accent follow the project (sessions are named after projects, so every
# jump syncs `theme mascot` in the background — jumps stay instant).
# Every jumper goes through here: rail element jumps, alt+L. A jump path
# that bypasses this leaves the wrong mascot on screen.
#
#   goto-pane.sh <session> <window-target> <pane-target> [quiet|strict]
#   goto-pane.sh back
#
# History (@TMUX_CURR_PANE/@TMUX_PREV_PANE) is maintained by the in-server
# focus hooks in tmux.conf. One logical jump raises up to three focus
# events (switch-client, select-window, select-pane) whose partial views
# would each shift history, so the jump holds @TMUX_HIST_LOCK — the hooks
# skip locked events — and makes one authoritative write itself, below.

if [ "${1:-}" = back ]; then
  # `back` jumps to @TMUX_PREV_PANE (alt+L). Pane ids are stable, so a
  # target that no longer resolves is really gone — not renumbered. No
  # hook can reap dead panes from history (pane-exited formats the
  # SURVIVING pane, never the dying one), so stale entries are dropped
  # here, silently: a keystroke that found nothing is not worth a modal.
  origin="$(tmux display-message -p '#{pane_id}|#{?#{@rail},rail,content}|#{pane_floating}' 2>/dev/null)"
  prev="$(tmux show-options -gqv @TMUX_PREV_PANE)"
  [ -n "$prev" ] || exit 0
  case "$prev" in
  %*) ;;
  *)
    # The old implementation stored session:window.pane locations; drop
    # them without a misleading status message.
    tmux set-option -gu @TMUX_PREV_PANE
    exit 0
    ;;
  esac
  prev_info="$(tmux display-message -p -t "$prev" \
    '#{pane_id}|#{?#{@rail},rail,content}|#{pane_floating}|#{session_name}' 2>/dev/null)"
  prev_id="${prev_info%%|*}"
  rest="${prev_info#*|}"
  prev_kind="${rest%%|*}"
  rest="${rest#*|}"
  prev_floating="${rest%%|*}"
  prev_session="${rest#*|}"
  # A dead, rail, or floating previous pane must never be exposed to
  # alt+L: rail and floating panes are display surfaces, not destinations.
  if [ -z "$prev_info" ] || [ "$prev_id" != "$prev" ] ||
    [ "$prev_kind" != content ] || [ "$prev_floating" = 1 ] ||
    [ -z "$prev_session" ]; then
    tmux set-option -gu @TMUX_PREV_PANE
    exit 0
  fi
  session="$prev_session"
  window="$prev"
  pane="$prev"
  quiet=quiet
else
  session="$1"
  window="$2"
  pane="$3"
  quiet="${4:-}"
  origin=""
fi

notify() {
  case "$quiet" in
  quiet | strict) return 0 ;;
  esac
  tmux display-message "$1"
}

target_failed() {
  notify "$1"
  [ "$quiet" = strict ] && exit 1
  exit 0
}

# Validate the whole target before moving anything: the jump chain below
# stops at its first failing command, so a dead target must fail HERE to
# be a clean no-op instead of a half-jump. Emptiness is the pane
# aliveness test: display-message exits 0 for a dead target, printing
# nothing.
if ! tmux has-session -t "=$session" 2>/dev/null; then
  target_failed "goto-pane: session '$session' is gone"
fi
if [ -z "$(tmux display-message -p -t "$pane" '#{pane_id}' 2>/dev/null)" ]; then
  target_failed "goto-pane: target pane is gone"
fi

# Capture the client's REAL pane before anything moves (no -t: callers
# run inside the origin pane, so TMUX_PANE resolves it). The jump knows
# its own origin, so it records it — one jump, one authoritative write.
[ -n "$origin" ] || origin="$(tmux display-message -p '#{pane_id}|#{?#{@rail},rail,content}|#{pane_floating}' 2>/dev/null)"

# A crash between taking and releasing the lock would leave the hooks
# skipping every focus event; the trap releases it on any exit path.
# Redundant after the success chain below unsets it — and harmless.
trap 'tmux set-option -gu @TMUX_HIST_LOCK' EXIT

# One chained invocation: the lock lands in the same command queue slot
# as the moves, so no hook can observe the jump unlocked. tmux stops a
# chain at its first failing command and exits nonzero, so a target that
# vanished since validation cannot become a wrong-session window hop.
if ! tmux set-option -g @TMUX_HIST_LOCK 1 \; \
  switch-client -t "=$session" \; \
  select-window -t "$window" \; \
  select-pane -t "$pane"; then
  target_failed "goto-pane: target vanished mid-jump"
fi

# The authoritative history write: the hooks skipped every event above,
# so CURR must be written here. A recordable origin (a content,
# non-floating pane other than the target) is written as PREV directly —
# the jump knows where it came from. Otherwise — rail/floating origin,
# failed capture, or a caller whose TMUX_PANE already sits on the
# target — PREV takes the pre-jump CURR only if the jump really moved:
# in-server, via the same format the hooks use, so a display surface
# still never enters history and a jump-in-place still shifts nothing.
origin_pane="${origin%%|*}"
origin_rest="${origin#*|}"
origin_kind="${origin_rest%%|*}"
origin_floating="${origin_rest#*|}"
if [ "$origin_kind" = content ] && [ "$origin_floating" != 1 ] &&
  [ -n "$origin_pane" ] && [ "$origin_pane" != "$pane" ]; then
  tmux set-option -g @TMUX_PREV_PANE "$origin_pane" \; \
    set-option -g @TMUX_CURR_PANE "$pane" \; \
    set-option -gu @TMUX_HIST_LOCK
else
  tmux set-option -gF @TMUX_PREV_PANE \
    "#{?#{==:#{@TMUX_CURR_PANE},$pane},#{@TMUX_PREV_PANE},#{@TMUX_CURR_PANE}}" \; \
    set-option -g @TMUX_CURR_PANE "$pane" \; \
    set-option -gu @TMUX_HIST_LOCK
fi

("$HOME/.local/bin/theme" mascot sync "$session" >/dev/null 2>&1 &)
