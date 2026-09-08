#!/bin/sh
# Land on the code workspace and focus the terminal there — by window.
#
# `open -a Ghostty` activates the application, and macOS raises its most
# recently used window, on whichever monitor that is. With a terminal on two
# monitors that is the wrong one often enough to notice. AeroSpace has the
# same race with multi-monitor apps inside its own focus command
# (nikitabobko/AeroSpace#101), so this cannot make it vanish, but naming the
# window keeps AeroSpace in charge instead of handing the choice to macOS.
# The app path remains only for a workspace with no terminal yet.
#
# Called by the cmd-alt-a / cmd-alt-r chords in aerospace.toml and by the A
# and R letters in sketchybarrc, ahead of the rail command each of them runs.
set -eu

aerospace workspace code >/dev/null
window="$(aerospace list-windows --workspace code \
  --app-bundle-id com.mitchellh.ghostty --format '%{window-id}' 2>/dev/null |
  head -n 1)"
if [ -n "$window" ]; then
  aerospace focus --window-id "$window"
else
  open -a Ghostty
fi
