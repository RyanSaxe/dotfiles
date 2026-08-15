#!/bin/sh
# Reassert the rail's fixed width the moment a layout reflow disturbs it.
# window-size latest means a client switch resizes windows to the new
# client's dimensions and scales panes proportionally, dragging the rail
# off spec until the daemon's next tick — a visible column wobble. Hook
# instant, daemon inevitable (selfHeal remains the backstop).
#
# 24 mirrors RAIL_WIDTH in tuis/rail/src/daemon.ts (22 content + 2
# gutter). Resizing back to 24 re-fires the layout hook once; the width
# check makes that pass a no-op, so it terminates.
set -eu

window="${1:?usage: heal-rail-width.sh <window_id>}"

tmux list-panes -t "$window" -F '#{pane_id} #{@rail} #{pane_width}' 2>/dev/null |
  while read -r pane is_rail width; do
    [ "$is_rail" = "1" ] || continue
    [ "$width" = "24" ] || tmux resize-pane -t "$pane" -x 24 2>/dev/null || true
  done
