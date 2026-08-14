# rail

In-terminal sidebar: this session's tmux windows plus every agent
everywhere, themed by the dotfiles theme system, wearing each project's
pokemon. Cross-platform — anywhere tmux runs, the rail runs.

## How it works

One daemon (`src/daemon.ts`) renders a frame per (session, geometry) and
writes it straight to each rail pane's tty. The panes themselves hold only
`tail -f /dev/null` (~500KB): tmux interprets the tty writes into its own
screen buffer, so frames survive detach/attach and remote clients with no
viewer process at all. Frames are diffed per pane and committed under
synchronized output — an unchanged rail costs zero writes and repaints
never flicker.

- **tmux data** polls every 250ms (one `list-panes -a` call).
- **Agents** come from `workmux status --json` (run from `$HOME` for the
  global view), reconciled every 5s with instant refreshes when a workmux
  state file changes.
- **Theme** re-reads `tuis-colors.json` on change; a mode or pokemon
  switch recolors every rail within a tick.

## The grammar

- Chip = place: number chips mirror `alt+N`; the accent-filled chip is the
  current window and nothing else.
- Title color = state: mauve working, peach waiting, green done. No bold.
- Elsewhere (other sessions' agents) sits at one uniform dim level,
  urgency-sorted: waiting, working, done, acked.
- Visit-clears acks: seeing an agent's window silences its done/waiting
  color everywhere until a new status event (`src/acks.ts`).
- Jump hints: every agent gets a letter chip; `alt+;` then the letter
  jumps to that agent's pane (`src/hints.ts`, `rail jump`).
- The footer is the mascot's home: the project's pokemon sprite via kitty
  graphics, placed only while the window is visible on an attached client
  (`src/mascot.ts`).

## Commands

```sh
rail on|off|toggle    # enable/disable + spawn/kill rail panes everywhere
rail attach <window>  # tmux hooks call this for new windows/sessions
rail jump <letter>    # hint jump (bound to alt+; <letter>)
rail status           # daemon, flag, pane count
```

The CLI lives in the `rail` stow package (`rail/.local/bin/rail`);
`install.sh` core installs node and this package's dependencies.

## Iterating on the look

`dev/` holds the loop used to judge cells without touching a live client:

```sh
npx tsx dev/goldframe.ts | uv run -q --script dev/ansi2png.py frame.png
XDG_STATE_HOME=$(mktemp -d) npx tsx dev/ackcheck.ts   # ack lifecycle
npx tsx dev/mascotcheck.ts <sprite.png>               # kitty sequences
```

`TUIS_COLORS_PATH` pins an alternate palette (light-mode checks);
`RAIL_WIDTH`/`RAIL_HEIGHT`/`RAIL_ACK` shape the fixture scene.

## TODO

- Multi-agent windows render only the first agent; stacked-row design
  awaits a verdict (see the rail design artifacts).
- `workmux status --json` does not export interrupted/stale states; if
  they land upstream, consume them instead of local detection.
- Future tabs (todos, review queue, PR checks) join as sibling sections
  cycled by an external tmux bind.
