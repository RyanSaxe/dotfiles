# theme [dark|light] switches every app between light and dark. Given a
# mode, it sets macOS's appearance first, so macOS, Rex and Ghostty's
# colors change too. Without one it follows macOS, which is how sketchybar
# runs it when the appearance changes and how each home switch runs it.
#
# Each home switch renders every theme file for both modes, into
# ~/.config/theme/dark and light. Apps read the link of the same name
# beside them, so a flip only moves links, then reloads the apps that keep
# colors in memory.

dir="$HOME/.config/theme"
case "${1:-}" in
dark | light)
  mode=$1
  if [[ $OSTYPE == darwin* ]]; then
    dark=false
    [[ $mode == dark ]] && dark=true
    /usr/bin/osascript -e "tell application \"System Events\" to tell appearance preferences to set dark mode to $dark"
  fi
  ;;
"")
  if [[ $OSTYPE == darwin* ]]; then
    mode=light
    if /usr/bin/defaults read -g AppleInterfaceStyle 2>/dev/null | grep -q Dark; then mode=dark; fi
  else
    # No system appearance to follow, so keep the last mode.
    mode=$(cat "$dir/mode" 2>/dev/null || echo dark)
  fi
  ;;
*)
  echo "usage: theme [dark|light]" >&2
  exit 2
  ;;
esac
if [[ ! -d "$dir/$mode" ]]; then
  echo "theme: $dir/$mode is missing, and home-switch renders it" >&2
  exit 1
fi

# Each link is swapped in whole, so an app never reads a half-moved file.
for file in "$dir/$mode"/*; do
  name=${file##*/}
  ln -sfn "$mode/$name" "$dir/.$name.new"
  mv -f "$dir/.$name.new" "$dir/$name"
done
echo "$mode" >"$dir/.mode.new"
mv -f "$dir/.mode.new" "$dir/mode"

# tmux, Ghostty and sketchybar keep colors in memory, so each re-reads its
# own. tmux servers are sockets in tmux's folder, which /tmp and
# /private/tmp can both name on macOS. A stale socket is skipped.
seen=""
for sockets in "${TMUX_TMPDIR:-/tmp}/tmux-$(id -u)" "/private/tmp/tmux-$(id -u)"; do
  [[ -d $sockets ]] || continue
  if [[ -n $seen && $sockets -ef $seen ]]; then continue; fi
  seen=$sockets
  for socket in "$sockets"/*; do
    [[ -S $socket ]] || continue
    if tmux -S "$socket" source-file -q "$dir/tmux-colors.conf" 2>/dev/null; then
      tmux -S "$socket" list-clients -F '#{client_name}' 2>/dev/null |
        while read -r client; do
          tmux -S "$socket" refresh-client -t "$client" -S 2>/dev/null || true
        done
    fi
  done
done
pkill -USR2 -x ghostty 2>/dev/null || true
# Last, since sketchybar may be the one running this.
sketchybar=${SKETCHYBAR:-$(command -v sketchybar || true)}
if [[ -n $sketchybar ]]; then "$sketchybar" --reload 2>/dev/null || true; fi
