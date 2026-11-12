# ws

`ws` opens folders, worktrees and pull requests as Rex or tmux sessions,
and draws the popups that move between them.

`ws` can grow, but keep it lean. A feature earns its lines by doing
something Ryan uses every day, extends a popup or command that exists before
it adds one, and reuses the frame every popup shares. If a change makes `ws`
noticeably bigger, say why in its commit message and look for what can go.

`ws` is a core and the popups built on it. The core is five packages that
know nothing about Pokémon, pull requests or the vault, so they could be
packaged on their own:

- `popup`: the frame every popup shares, fzf's matching, terminal captures
- `kitty`: images drawn with Kitty's Unicode placeholders
- `markdown`: markdown for a pane, with pictures and mermaid diagrams
- `mux`: Rex and tmux sessions, what their panes are doing, agent statuses
- `layout`: session layouts and shell quoting

The command in this folder holds everything that knows Ryan's setup: the CLI,
each popup as a `popup.Popup` value, worktrees, attention, the vault's
tasks, the mascot, and GitHub's private images. The core never imports it,
and settings the core needs, such as the backend or whether the terminal
draws images, are passed in rather than read from globals.

## What ws keeps

State lives with the tools. git owns worktrees and branches, Rex and tmux
own sessions and agent statuses, and gh owns pull requests. `ws` asks them
each time and keeps no copy. What it does keep is in `~/.local/state/ws`.
`XDG_STATE_HOME` moves that folder, so a scratch run can use its own.

`ws attention --watch` runs as a launchd agent on each Mac with the `gui`
role, and writes the files sketchybar and Reviews read:

- `inbox.json`: the pull requests and issues Reviews lists, as the job last
  fetched them from GitHub
- `agent-attention` and `review-attention`: the levels the job last
  published for sketchybar's A and R
- `attention.pid`: the job's process ID, which Reviews signals to fetch now

The rest are records `ws` keeps for itself:

- `acknowledged.json`: each item you marked done in Reviews, with what it
  needed you for then, so that anything newer brings it back
- `last-jump`: the Rex pane the last `ws attention --jump` went to, so the
  next jump moves on
- `mascot.json`: the mascot and its two colors, which only the popups use,
  written by `ws mascot` and the theme popup
- `agent`: the agent this computer starts by default, set by `ws agent`

Mascot pictures from PokeAPI and drawn mermaid diagrams are caches, in
`~/.cache/dotfiles`. `ws` reads layouts from `~/.config/ws/layouts`, extra
folders for the go popup from `~/.config/ws/bookmarks`, and local mascots
from `~/.local/share/dotfiles/mascots`.

## Rules

- Each file has one writer, which swaps it in whole. Only the `--watch` job
  fetches the inbox, and Reviews asks it to with a signal.
- Anything `ws` must track itself is a named type that lists its states,
  with one function that moves between them. Never spread flags across the
  code to stand for a state.
- Tests guard what a popup author or a person relies on, through the
  packages' public API: what Load, Fetch and the actions receive, what Esc
  does, the order Match ranks in. They never assert on private fields or
  rendered text.
- A new feature states its cost in lines in its commit message.
- Delete a feature nobody uses, rather than keep it working.

## Checking a change

Check a change with `go vet ./...`, `gofmt -l .` and `go test ./...`, then
build it from the repository root with `nix build .#ws`. Try a popup in a
scratch Rex session or a `tmux -L` server, never your working ones.
