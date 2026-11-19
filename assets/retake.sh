#!/usr/bin/env bash
# Retakes every screenshot the README and the docs show, with demo content:
#
#   assets/screen.png        the screen: sketchybar, and Rex with two Neovim
#                            panes, on a Python file and on a note
#   assets/screen-dark.png   the same shot, for docs/theme.md
#   assets/screen-light.png  the same screen in light mode
#   assets/picker.png        the go popup on Folders
#   assets/inbox.png         the Inbox popup on Needs you, with sketchybar's
#                            R lit
#
#   assets/retake.sh          take them. This takes over the screen for a
#                             few minutes and flips the theme, so don't type
#                             meanwhile.
#   assets/retake.sh --check  print each popup's and each Neovim pane's text
#                             from a scratch tmux server instead. Nothing on
#                             the screen changes.
#
# Run it by hand on a Mac: it needs Rex's window, your fonts, your theme and
# sketchybar, so it can't run in CI.
#
# It builds this checkout's ws, and demo repositories, a demo inbox and a
# demo vault in a scratch folder. The popups run with HOME and the XDG
# folders set to that folder, and Neovim opens only files in it, so nothing
# of yours is in a shot or changed. The shots are of Rex on AeroSpace's code
# workspace, in a session named atlas that the script makes and kills.
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
# Rex heads each pane with its folder, so the scratch folder has a short
# path.
scratch=$(mktemp -d /tmp/retake.XXXX)
demo=$scratch/home
session=""
trap 'rm -rf "$scratch"' EXIT

stop() {
  echo "retake: $*" >&2
  exit 1
}

# The commands, as they are run with the demo's folders in place of yours.
in_demo() {
  env HOME="$demo" XDG_CONFIG_HOME="$demo/.config" XDG_STATE_HOME="$demo/.local/state" \
    XDG_CACHE_HOME="$demo/.cache" XDG_DATA_HOME="$demo/.local/share" VAULT_DIR="$demo/vault" \
    PATH="$ws/bin:$PATH" "$@"
}

# git with no settings or hooks but the demo's, and no repository from the
# environment, so a commit can only land in the demo.
demo_git() {
  env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE HOME="$demo" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
    git -c user.name=Demo -c user.email=demo@example.com -c core.hooksPath=/dev/null -c commit.gpgsign=false \
    -c init.defaultBranch=main "$@"
}

# demo_repo NAME MINUTES SUBJECT... makes ~/code/NAME with one commit per
# subject, last active MINUTES ago.
demo_repo() {
  local name=$1 minutes=$2 dir=$demo/code/$1
  shift 2
  mkdir -p "$dir"/{src,docs,tests}
  printf '# %s\n' "$name" >"$dir/README.md"
  printf '[project]\nname = "%s"\n' "$name" >"$dir/pyproject.toml"
  printf 'def main() -> None:\n    print("%s")\n' "$name" >"$dir/src/$name.py"
  printf 'from %s import main\n' "$name" >"$dir/tests/test_$name.py"
  printf '# Design\n' >"$dir/docs/design.md"
  demo_git -C "$dir" init -q
  demo_git -C "$dir" remote add origin "git@github.com:example/$name.git"
  demo_git -C "$dir" add -A
  for subject in "$@"; do
    demo_git -C "$dir" commit -q --allow-empty -m "$subject"
  done
  aged "$dir/.git/logs/HEAD" "$minutes"
}

# ws reads a folder's last activity off the time of git's log file.
aged() {
  touch -t "$(date -v-"$2"M +%Y%m%d%H%M)" "$1"
}

build_demo() {
  mkdir -p "$demo"/{.config/ws,.config/sops-nix/secrets,.local/state/ws,vault/notes/projects/atlas,vault/notes/daily,notes}
  # The popups' colors and sketchybar's are the theme's, which holds nothing
  # private.
  ln -s "$HOME/.config/theme" "$demo/.config/theme"
  ln -s "$repo/config/sketchybar" "$demo/.config/sketchybar"

  demo_repo atlas 12 "feat: draw routes as the map loads" "fix: keep the zoom level across reloads" "docs: say how tiles are cached"
  demo_repo ledger 95 "feat: import statements as CSV" "fix: round each split to the cent"
  demo_repo tide 400 "feat: forecast a week ahead" "test: cover a station with no data"
  demo_repo quill 3000 "feat: export a note as a PDF" "fix: keep a table's alignment"
  demo_repo harbor 9000 "chore: update the lock file"
  demo_files
  demo_git -C "$demo/code/atlas" commit -qam "feat: list the tiles a viewport needs"
  aged "$demo/code/atlas/.git/logs/HEAD" 12
  demo_git -C "$demo/code/atlas" worktree add -q -b fix-login "$demo/worktrees/atlas/fix-login"
  aged "$demo/code/atlas/.git/worktrees/fix-login/logs/HEAD" 40
  echo "~/notes" >"$demo/.config/ws/bookmarks"

  # Watching is a tab only on a computer that watches repositories.
  echo "example/tide" >"$demo/.config/sops-nix/secrets/attention-watch"
  jq -n '
    def ago(hours): (now - hours * 3600) | todate;
    def pr(n; repo; title; head; hours; reasons): {
      ID: "\(repo)#\(n)", Number: n, Repo: "example/\(repo)", URL: "https://github.com/example/\(repo)/pull/\(n)",
      Title: title, HeadRef: head, BaseRef: "main", Updated: ago(hours), Reasons: reasons,
      Additions: (n * 3 % 200 + 20), Deletions: (n % 40), Files: (n % 7 + 2),
      Checks: [{Name: "test", Result: "pass"}, {Name: "lint", Result: "pass"}]};
    {Fetched: (now | todate), Items: [
      pr(182; "atlas"; "Keep the zoom level across reloads"; "keep-zoom"; 20;
          [{Kind: 0, Actor: "test (ubuntu-latest)", At: ago(20), Key: "c1"}])
        + {Yours: true, Decision: "REVIEW_REQUIRED", Checks: [{Name: "test (ubuntu-latest)", Result: "fail"}, {Name: "lint", Result: "pass"}],
           Body: "The map kept its center across a reload and lost its zoom level."},
      pr(151; "ledger"; "Round each split to the cent"; "round-splits"; 26;
          [{Kind: 1, Actor: "mira-k", At: ago(26), Key: "r1",
            Text: "A split of three still loses a cent: 10.00 comes out as 3.33 three times. Could the last share take the remainder, the way `allocate` does?"}])
        + {Yours: true, Decision: "CHANGES_REQUESTED",
           Body: "Each share of a split is rounded to the cent as it is written.\n\n- `split` rounds half to even\n- `import` uses it for every row\n- The total is checked against the statement\n\n```python\nshare = round(amount / people, 2)\n```\n\nThe failing statement is in the first comment."},
      pr(188; "atlas"; "Draw routes as the map loads"; "routes-first"; 30;
          [{Kind: 2, Actor: "sam-ortiz", At: ago(30), Key: "r2", Text: "Looks right to me."}])
        + {Yours: true, Decision: "APPROVED", Body: "Routes draw before the tiles under them finish loading."},
      {ID: "tide#47", Number: 47, Repo: "example/tide", URL: "https://github.com/example/tide/issues/47", Issue: true, Yours: true,
       Title: "A station with no data stops the forecast", Updated: ago(31), Body: "The week ahead is empty when one station reports nothing.",
       Reasons: [{Kind: 3, Actor: "sam-ortiz", At: ago(31), Key: "c2", Text: "I see this too, on every station north of the bay."}]},
      {ID: "quill#52", Number: 52, Repo: "example/quill", URL: "https://github.com/example/quill/issues/52", Issue: true, Yours: true,
       Title: "Draw Mermaid diagrams in an exported PDF", Updated: ago(50), Body: "A diagram exports as its source.",
       Reasons: [{Kind: 3, Actor: "devon-l", At: ago(50), Key: "c3", Text: "Would a picture at the page width do?"}]},
      pr(64; "tide"; "Forecast a week ahead"; "week-ahead"; 28;
          [{Kind: 4, Actor: "priya-n", At: ago(28), Key: "o1"}])
        + {Author: "priya-n", Watched: true, Decision: "REVIEW_REQUIRED", Body: "The forecast runs seven days from the last reading."},
      pr(190; "ledger"; "Import statements as CSV"; "csv-import"; 70; [])
        + {Yours: true, Draft: true, Body: "Reads a bank statement saved as CSV."}
    ]}' >"$demo/.local/state/ws/inbox.json"

  cat >"$demo/vault/notes/projects/atlas/TODO.md" <<EOF
# atlas

- [ ] Renew the tile server's certificate 📅 $(date -v-1d +%F)
- [ ] Reply to the review on the zoom fix 📅 $(date +%F)
- [ ] Measure a cold load on a phone 📅 $(date -v+3d +%F)
- [ ] Write up how tiles are cached

## fix-login

- [ ] Ask for a login only once per session
EOF
  cat >"$demo/vault/notes/daily/$(date +%F).md" <<EOF
# $(date +%F)

- [ ] Book the dentist 📅 $(date -v+1d +%F)
- [ ] Send the ledger export to the accountant 📅 $(date -v+12d +%F)
EOF
  # Neovim's breadcrumb starts at a note's repository, and the vault is one.
  demo_git -C "$demo/vault" init -q
  demo_git -C "$demo/vault" add -A
  demo_git -C "$demo/vault" commit -qm "notes"
  aged "$demo/vault/.git/logs/HEAD" 200
}

# demo_files writes what the two Neovim panes show.
demo_files() {
  cat >"$demo/code/atlas/src/atlas.py" <<'EOF'
"""Draws a map's routes over its tiles as the tiles load."""

import math
from collections.abc import Iterator
from dataclasses import dataclass

TILE_SIZE = 256


@dataclass(frozen=True)
class Tile:
    """One square of the map at a zoom level, counted from the top left."""

    zoom: int
    column: int
    row: int

    def children(self) -> Iterator["Tile"]:
        """The four tiles that cover this one at the next zoom level."""
        for column in (2 * self.column, 2 * self.column + 1):
            for row in (2 * self.row, 2 * self.row + 1):
                yield Tile(self.zoom + 1, column, row)


def tile_at(latitude: float, longitude: float, zoom: int) -> Tile:
    """Find the tile that holds a point, in the Web Mercator projection."""
    scale = 2**zoom
    column = (longitude + 180) / 360 * scale
    radians = math.radians(latitude)
    row = (1 - math.asinh(math.tan(radians)) / math.pi) / 2 * scale
    return Tile(zoom, int(column), int(row))


class Viewport:
    """The part of the map on screen, and the tiles it needs."""

    def __init__(self, width: int, height: int, zoom: int) -> None:
        self.width = width
        self.height = height
        self.zoom = zoom
        self.center = (0.0, 0.0)

    def tiles(self) -> list[Tile]:
        """List the tiles that cover the screen, nearest the center first."""
        middle = tile_at(*self.center, self.zoom)
        across = math.ceil(self.width / TILE_SIZE / 2)
        down = math.ceil(self.height / TILE_SIZE / 2)
        found = [
            Tile(self.zoom, middle.column + dx, middle.row + dy)
            for dx in range(-across, across + 1)
            for dy in range(-down, down + 1)
        ]
        return sorted(found, key=lambda t: abs(t.column - middle.column) + abs(t.row - middle.row))
EOF
  cat >"$demo/vault/notes/projects/atlas/tiles.md" <<'EOF'
# How atlas loads tiles

The map asks for the tiles under the screen, nearest the center first, and
draws each route as soon as the tiles under it arrive.

```mermaid
flowchart LR
  screen[Viewport] --> wanted[Tiles it needs]
  wanted --> cache{In the cache?}
  cache -->|yes| draw[Draw]
  cache -->|no| fetch[Fetch] --> draw
```

A point's tile comes from the Web Mercator projection, at zoom level $z$:

$$
x = \left\lfloor \frac{\lambda + 180}{360} \cdot 2^z \right\rfloor
$$

```python
tile = tile_at(latitude=47.6, longitude=-122.3, zoom=12)
```
EOF
}

# check prints each popup as a 200 by 50 terminal draws it, from a scratch
# tmux server, then the two files as your Neovim opens them. tmux draws no
# pictures, so the note's diagram and formula print as their source.
check() {
  local server="retake-$$" name file
  for name in go inbox tasks; do
    in_demo tmux -L "$server" -f /dev/null new-session -d -x 200 -y 50 -c "$demo/code/atlas" "ws pick $name"
    sleep 3
    echo "== ws pick $name"
    tmux -L "$server" capture-pane -p | sed -e 's/[[:space:]]*$//' -e '/^$/d'
    tmux -L "$server" kill-server
  done
  for file in code/atlas/src/atlas.py vault/notes/projects/atlas/tiles.md; do
    tmux -L "$server" -f /dev/null new-session -d -x 100 -y 40 -c "$demo" "nvim $file"
    sleep 5
    echo "== nvim $file"
    tmux -L "$server" capture-pane -p | sed -e 's/[[:space:]]*$//' -e '/^$/d'
    # Neovim quits on its own, so it stops the programs it started.
    tmux -L "$server" send-keys Escape ':qa!' Enter
    sleep 1
    tmux -L "$server" kill-server 2>/dev/null || true
  done
}

# The Rex app's client, or nothing when no app is connected.
app_client() {
  rex client ls --json | jq -r '[.clients[] | select(.info.kind == "app" and .info.platform == "macos") | .client_id] | last // empty'
}

rex_windows() {
  aerospace list-windows --monitor all --app-bundle-id com.superlogical.rex --format '%{window-id}|%{window-title}' |
    awk -F'|' '$2 !~ /^Settings/'
}

# The demo session's pane with a label the script gave it.
labeled_block() {
  rex block ls -s "$session" --json | jq -r --arg label "$1" '[.blocks[] | select(.label == $label) | .block_id] | first // empty'
}

# open_popup NAME opens `ws pick NAME` in a float over the demo session, the
# size Rex's own ws keys give it, and waits for the app to draw it: a new
# float is 80 by 24 until then, so the popup's frame is that narrow.
open_popup() {
  local label="retake $1" command lua block columns
  command=$(printf '"%s", ' env "HOME=$demo" "XDG_CONFIG_HOME=$demo/.config" "XDG_STATE_HOME=$demo/.local/state" \
    "XDG_CACHE_HOME=$demo/.cache" "XDG_DATA_HOME=$demo/.local/share" "VAULT_DIR=$demo/vault" "$ws/bin/ws" pick "$1")
  lua="local _, err = rex.session.new_layer({ bounds = { 0.08, 0.08, 0.84, 0.84 }, focus = true,
    layout = rex.layout.block({ flavor = 'com.superlogical.terminal.shell', label = '$label',
      options = { command = { $command }, cwd = '$demo/code/atlas' } }) })
    if err ~= nil then error(err, 0) end"
  rex do -s "$session" -b "$code" -e "$lua" >/dev/null
  for _ in $(seq 1 40); do
    sleep 0.5
    block=$(labeled_block "$label")
    [ -n "$block" ] || continue
    # The popup's bottom border is as wide as the pane. grep finds none
    # until the popup draws.
    columns=$(rex capture -s "$session" -b "$block" | grep '^╰' | head -1 | LC_ALL=en_US.UTF-8 wc -m) || continue
    [ "$columns" -le 100 ] || return 0
  done
  stop "the $1 popup never grew past 80 columns, so the app isn't drawing it"
}

close_popup() {
  local block
  block=$(labeled_block "retake $1")
  [ -z "$block" ] || rex send-key -s "$session" -b "$block" escape >/dev/null
  sleep 1
}

# letters AGENT REVIEW TASK lights sketchybar's A, R and T as its own plugins
# would at those levels, by running them on the demo's state.
letters() {
  local name level
  for name in agent review task; do
    level=$1
    shift
    printf %s "$level" >"$demo/.local/state/ws/$name-attention"
    HOME="$demo" NAME="space.$name" zsh "$repo/config/sketchybar/plugins/$name.sh"
  done
}

# sketchybar's clock turns red at minutes 59, 00, 29 and 30, and its CPU
# readout lights above 50%, so a shot waits both out. It waits from
# the minute before a red one, so it can't run into it.
calm() {
  local cpu
  while case $(date +%M) in 58 | 59 | 00 | 28 | 29 | 30) true ;; *) false ;; esac do sleep 5; done
  sketchybar --trigger system_woke # draws the clock now, not at its next minute
  for _ in $(seq 1 30); do
    cpu=$(sketchybar --query cpu | jq -r .label.value | tr -dc 0-9)
    [ -n "$cpu" ] && [ "$cpu" -le 50 ] && return
    sleep 2
  done
  stop "the CPU stayed above 50% for a minute, which lights sketchybar's readout, so run this when the computer is less busy"
}

# capture FILE... takes the screen into each of assets' FILEs, and refuses a
# shot that would show another app, the Wi-Fi network's name or a frozen Rex.
capture() {
  local raw=$scratch/shot.png width file
  rex -C "$app" do client.notice.dismiss >/dev/null 2>&1 || true # Rex's "Update installed" notice
  sketchybar --set wifi label="Wi-Fi"
  calm
  sleep 1
  [ "$(aerospace list-workspaces --focused)" = code ] || stop "the code workspace lost focus"
  [ -z "$(aerospace list-windows --workspace code --format '%{app-bundle-id}' | grep -v '^com.superlogical.rex$')" ] ||
    stop "another app's window is on the code workspace, and would be in the shot"
  [ "$(aerospace list-windows --focused --format '%{app-bundle-id}')" = com.superlogical.rex ] || stop "Rex lost focus to another app"
  [ "$(app_client)" = "$app" ] || stop "Rex's app stopped answering. Relaunch Rex yourself, then run this again"
  screencapture -x -m "$raw"
  [ "$(sketchybar --query wifi | jq -r .label.value)" = "Wi-Fi" ] || stop "sketchybar wrote the Wi-Fi network's name during the shot"
  width=$(sips -g pixelWidth "$raw" | awk '/pixelWidth/ { print $2 }')
  [ "$width" -le 1920 ] || sips --resampleWidth 1920 "$raw" >/dev/null
  for file in "$@"; do
    nix run --inputs-from "$repo" nixpkgs#pngquant -- --quality 85-98 --speed 1 --force --output "$repo/assets/$file" "$raw"
    echo "retake: wrote assets/$file"
  done
}

# shoot_screen FILE... takes the two Neovim panes with no letter lit.
# Neovim draws the note's diagram for the mode it is in while its pane has
# the focus, so the note gets it for a moment first.
shoot_screen() {
  letters none none none
  rex -C "$app" focus -s "$session" "$note" >/dev/null
  sleep 5
  rex -C "$app" focus -s "$session" "$code" >/dev/null
  sleep 1
  capture "$@"
}

# shoot_popup NAME FILE takes the screen with `ws pick NAME` open.
shoot_popup() {
  open_popup "$1"
  # The second row has a review comment to show beside the list.
  [ "$1" = go ] || rex send-key -s "$session" -b "$(labeled_block "retake $1")" down >/dev/null
  capture "$2"
  close_popup "$1"
}

# Every window's workspace, app and title. A title can hold any character
# but this separator.
sep=$'\037'
windows() {
  aerospace list-windows --all --format "%{window-id}${sep}%{workspace}${sep}%{app-bundle-id}${sep}%{window-title}"
}

# to_mode MODE flips the theme. The flip quits and reopens Chrome, whose
# windows come back with new IDs on the focused workspace, and takes the
# focus with them. So once Chrome has its windows again, each window that
# isn't Rex's goes back to the workspace a window of its app and title was
# on, or to the browser workspace, and Rex gets the focus back.
to_mode() {
  local id space bundle title want
  theme "$1" >/dev/null
  sleep 6
  for _ in $(seq 1 40); do
    [ "$(windows | grep -c "${sep}com.google.Chrome${sep}")" -ge "$chrome" ] && break
    sleep 0.5
  done
  windows | while IFS="$sep" read -r id space bundle title; do
    [ "$bundle" = com.superlogical.rex ] && continue
    want=$(awk -F"$sep" -v b="$bundle" -v t="${title:0:25}" '$3 == b && substr($4, 1, 25) == t { print $2; exit }' <<<"$placed")
    [ "$space" = "${want:-browser}" ] || aerospace move-node-to-workspace --window-id "$id" "${want:-browser}" >/dev/null 2>&1 || true
  done
  aerospace workspace code
  aerospace focus --window-id "${window%%|*}"
  sleep 1
}

appearance() {
  if [ "$(defaults read -g AppleInterfaceStyle 2>/dev/null)" = Dark ]; then echo dark; else echo light; fi
}

# restore puts back the mode, the session the app showed, the workspace and
# sketchybar, and ends the demo session. Neovim is asked to quit first, so
# it stops the programs it started.
restore() {
  local pane
  [ "$(appearance)" = "$mode" ] || to_mode "$mode" || true
  [ -z "$shown" ] || rex -C "$app" do session.select session_id="$shown" >/dev/null 2>&1 || true
  aerospace workspace "$workspace" || true
  for pane in $code $note; do
    rex send-key -s "$session" -b "$pane" escape >/dev/null 2>&1 || true
    rex send -s "$session" -b "$pane" $':qa!\r' >/dev/null 2>&1 || true
  done
  sleep 1
  [ -z "$session" ] || rex kill "$session" >/dev/null 2>&1 || true
  sketchybar --trigger agent_attention_change --trigger review_attention_change --trigger task_attention_change
  sketchybar --update
  rm -rf "$scratch"
}

for tool in jq git nix tmux; do
  command -v "$tool" >/dev/null || stop "$tool isn't installed"
done
ws=$(nix build "$repo#ws" --no-link --print-out-paths)
build_demo

if [ "${1:-}" = --check ]; then
  check
  exit
fi
[ $# -eq 0 ] || stop "the only argument is --check"

for tool in rex aerospace sketchybar screencapture sips zsh nvim theme; do
  command -v "$tool" >/dev/null || stop "$tool isn't installed"
done
app=$(app_client)
[ -n "$app" ] || stop "no Rex app is connected, so open Rex first"
window=$(rex_windows | head -1)
[ -n "$window" ] || stop "Rex has no window"
shown=$(rex ls --json | jq -r --arg label "${window##* - }" '[.sessions[] | select(.label == $label) | .session_id] | first // empty')
[ -n "$shown" ] || stop "Rex's window doesn't name the session it shows, so it couldn't be put back"
workspace=$(aerospace list-workspaces --focused)
mode=$(appearance)
placed=$(windows)
chrome=$(grep -c "${sep}com.google.Chrome${sep}" <<<"$placed" || true)
code="" note=""
rex ls --json | jq -e '[.sessions[] | select(.label == "atlas")] | length == 0' >/dev/null || stop "a session named atlas is already running"

trap restore EXIT
# The session is named after the demo repository it starts in, so the go
# popup tags that folder as open. Neovim runs your own setup, on the demo's
# Python file and, beside it, the demo's note.
made=$(rex new atlas -c "$demo/code/atlas" --json -- nvim src/atlas.py)
session=$(jq -r .session_id <<<"$made")
code=$(jq -r '.initial_windows[0].block_ids[0]' <<<"$made")
rex split -s "$session" -b "$code" -c "$demo/vault" --label "retake note" --focus=false -- nvim notes/projects/atlas/tiles.md >/dev/null
note=$(labeled_block "retake note")
[ -n "$note" ] || stop "the note's pane didn't open"

# Rex's window draws nothing new while its workspace is hidden, and
# switching it to a session then has frozen the app. So the workspace comes
# first.
aerospace workspace code
sleep 1
rex -C "$app" do session.select session_id="$session" >/dev/null
aerospace focus --window-id "${window%%|*}"
sleep 2
[ "$(app_client)" = "$app" ] || stop "Rex's app stopped answering. Relaunch Rex yourself, then run this again"

[ "$mode" = dark ] || to_mode dark
shoot_screen screen.png screen-dark.png
shoot_popup go picker.png
letters none review none
shoot_popup inbox inbox.png
to_mode light
shoot_screen screen-light.png
