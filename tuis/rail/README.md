# rail

In-terminal sidebar: this session's tmux windows plus every agent
everywhere, themed by the dotfiles theme system, wearing each project's
mascot. Cross-platform — anywhere tmux runs, the rail runs.

## How it works

One daemon (`src/daemon.ts`) renders a frame per (session, geometry) and
writes it straight to each rail pane's tty. The panes themselves hold only
`tail -f /dev/null` (~500KB): tmux interprets the tty writes into its own
screen buffer, so frames survive detach/attach and remote clients with no
viewer process at all. Frames are diffed per pane and committed under
synchronized output — an unchanged rail costs zero writes and repaints
never flicker.

- **tmux data** polls every 250ms (panes and clients in one
  `list-panes -a \; list-clients` call), backing off to 2s while the
  rail is disabled or no client is attached.
- **Agents** come from `workmux status --json` (run from `$HOME` for the
  global view), reconciled every 5s with instant refreshes when a workmux
  state file changes.
- **Theme** re-reads `tuis-colors.json` on change; an outer-mode or mascot
  switch recolors every rail within a tick.

## The grammar

- Chip = place: number chips mirror `alt+N`; the accent-filled chip is the
  current window and nothing else.
- Title color = state: mauve working, peach waiting, green done. No bold.
- Elsewhere (other sessions' agents) sits at one uniform dim level,
  urgency-sorted: waiting, working, done, acked.
- Visit-clears acks: seeing an agent's window — active, attached, and its
  terminal window holding OS focus (tmux's own `client_flags`, so it works
  over ssh) — silences its done/waiting color everywhere until a new
  status event (`src/acks.ts`).
- Jump hints: every agent gets a letter chip; `alt+;` then the letter
  jumps to that agent's pane (`src/hints.ts`, `rail jump`).
- Attention jump: `rail jump-attention` selects the highest-priority live
  pane from the daemon's stabilized, unacknowledged set. It uses pane ids, so
  a deleted pane is skipped instead of turning into a jump to another window.
- Overflow paginates by whole items (`alt+,` / `alt+.`); the page hint
  renders in the footer row above the sprite, so the
  list's spacing never changes.
- A two-cell crust gutter ends every row: text and the square tab divider stop ~19pt
  (the frame's spacing unit) before the content surface, mirroring the
  frame crust left of the session name.
- The footer is the mascot's home: the project's mascot sprite rendered
  through kitty-graphics Unicode placeholders (`src/sprite.ts`) — the PNG
  is transmitted once as a virtual placement and the footer cells anchor
  it, so tmux redraws, switches, and the toggle carry it like text and
  ghosting is structurally impossible. Sprites render only when every
  client attached to the session is a kitty-capable terminal (tmux's
  client table decides); otherwise the footer stays blank.

## Commands

```sh
rail on|off|toggle    # enable/disable + spawn/kill rail panes everywhere
                      # (on also turns the tmux status bar off; off restores)
rail jump <letter>    # hint jump (bound to alt+; <letter>)
rail jump-attention   # jump to the highest-priority pending agent
rail page up|down     # page an overflowing rail (bound to alt+, / alt+.)
rail dashboard reviews|tasks
                      # table + preview dashboard for a rail tab
rail ensure-daemon    # start the render daemon if it isn't running
rail status           # daemon, flag, pane count
```

The CLI lives in `tuis/rail/bin/rail`;
`install.sh` core installs node and this package's dependencies.

## Account-wide GitHub attention

The review observer is a separate process from the rail. On macOS, the core
install registers `com.ryansaxe.dotfiles.attention` with the user's launchd;
it runs `attention refresh` at login and every five minutes. It uses one
account-level `gh api graphql` request, writes durable state under
`~/.local/state/dotfiles/attention/`, and never requires an open repository,
tmux session, or Neovim.

```sh
attention status                 # refresh/error/rate/channel diagnostics
attention refresh --no-notify    # real fetch without a phone ping
attention list                   # current active items
attention ack <item-id>          # local check/dismiss, no GitHub mutation
```

The rail does not perform these network requests. The Reviews tab reads the
observer's cached state. `alt+r` selects the Reviews rail tab; the
tab is one compact line per unacknowledged item and highlights the Reviews badge
until the item is acknowledged or disappears. `alt+R` opens the cached Review
table + preview dashboard. `alt+t` selects the Tasks rail tab — the vault's
open work, urgency-ordered, with the tab itself red while anything is
overdue — and `alt+T` opens the same dashboard shell for it.

The Reviews dashboard has two views, switched with Tab:

| view      | rows                                      | keys                                                                                         |
| --------- | ----------------------------------------- | -------------------------------------------------------------------------------------------- |
| Reviews   | what needs you, grouped by repository     | `↵` open a review workspace · `b` browser · `d` diff · `a` assisted review · `x` acknowledge |
| Worktrees | pull requests already checked out locally | `↵` focus the session · `X` clean up                                                         |

`/` searches the table, `r` refreshes without notifying, and `ctrl-u`/`ctrl-d`
scroll the preview. Every key stays bound at any width; the footer only
advertises what fits.

`↵` on a review resolves the repository — cloning it into `~/repositories` if
it is not already on disk — and asks workmux for a worktree on the pull
request's branch, opening it as a `gh://` review buffer. No agent starts:
`a` is the only path that runs one, and it adds a window to that same
session rather than replacing the human one.

Acknowledged items leave the table rather than dimming. A new external event
arrives with a new id, so a cleared item returns on its own.

The tab registry is intentionally small: Agents, Reviews, and Tasks share one
element-action table. `alt+space` enters that table; the selected tab decides
what a number means. Agent elements jump to their pane, review elements open
their PR, and task elements open the note where the task is written, at its
line. A number never completes a task: ids are recomputed on every read, so
the Nth row of a frame that may be a refresh old is only ever aimed at
something safe. Completing is the dashboard's `x`, against a selected row.

## Iterating on the look

`scripts/` holds the loop used to judge cells without touching a live client,
and `tests/` holds the suite:

```sh
npx tsx scripts/goldframe.ts | uv run -q --script scripts/ansi2png.py frame.png
npm test                                            # the whole suite
```

`TUIS_COLORS_PATH` pins an alternate palette (light-mode checks);
`RAIL_WIDTH`/`RAIL_HEIGHT`/`RAIL_ACK`/`RAIL_PAGE` shape the fixture scene.

## TODO

- `workmux status --json` does not export interrupted/stale states; if
  they land upstream, consume them instead of local detection.
