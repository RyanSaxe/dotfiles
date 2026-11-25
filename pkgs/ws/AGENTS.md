# ws

`ws` opens folders, worktrees and pull requests in Rex or tmux sessions and
tabs, and draws the popups that move between them.

`ws` can grow, but keep it lean. A feature earns its lines by doing something
Ryan uses every day, extends a popup or command that exists before it adds one,
and reuses the frame every popup shares. If a change makes `ws` noticeably
bigger, say why in its commit message and look for what can go.

`ws` is a core and the popups built on it. The core is five packages that know
nothing about Pokémon, pull requests or the vault, so they could be packaged on
their own:

- `popup`: the frame every popup shares, fzf's matching, terminal captures
- `kitty`: images drawn with Kitty's Unicode placeholders
- `markdown`: markdown for a pane, with pictures and mermaid diagrams
- `mux`: Rex and tmux sessions, tabs and panes, read in one `Snapshot` with each
  pane's tab, what it runs, its agent's status and whether it needs you, the
  places folders are open in, and the actions on them
- `layout`: session layouts and shell quoting

The command in this folder holds everything that knows Ryan's setup: the CLI,
each popup as a `popup.Popup` value, worktrees, attention, the vault's tasks,
the mascot, and GitHub's private images. The core never imports it, and settings
the core needs, such as the backend or whether the terminal draws images, are
passed in rather than read from globals.

The Inbox popup is two halves joined by `inboxPopup` in `popups.go`: the reviews
tabs from `reviews.go`, then the Tasks tabs from `tasks.go`. Each half is a
`popup.Popup` that numbers its own tabs from 0, so a change to one half's tabs
or keys stays in its file.

## What ws keeps

State lives with the tools. git owns worktrees and branches, Rex and tmux own
sessions, tabs and agent statuses, and gh owns pull requests. `ws` asks them
each time and keeps no copy. What it does keep is in `~/.local/state/ws`.
`XDG_STATE_HOME` moves that folder, so a scratch run can use its own.

`ws attention --watch` runs as a launchd agent on each Mac with the `gui` role,
and writes the files sketchybar and the Inbox popup read:

- `inbox.json`: the pull requests and issues the Inbox lists, as the job last
  fetched them from GitHub
- `agent-attention`, `review-attention` and `task-attention`: the levels the job
  last published for sketchybar's A, R and T
- `attention.pid`: the job's process ID, which the Inbox signals to fetch now

The rest are records `ws` keeps for itself:

- `acknowledged.json`: each item you marked done in the Inbox, with what it
  needed you for then, so that anything newer brings it back
- `last-jump`: the pane the last `ws focus agent` went to, so the next jump
  moves on
- `seen.json`: each failed or done Rex report you were looking at as it came, by
  pane, so it doesn't need you once you look away. Only the `--watch` job writes
  it, and it keeps only panes that still exist
- `mascot.json`: the mascot and its accent, which only the popups use, written
  by `ws mascot` and the theme popup

Mascot pictures from PokeAPI and drawn mermaid diagrams are caches, in
`~/.cache/dotfiles`. `ws` reads its settings from `~/.config/ws`: `config.toml`,
which the home switch writes from the host file's `dotfiles.ws`, layouts in
`layouts`, and extra folders for the go popup in `bookmarks`. `XDG_CONFIG_HOME`
moves that folder. Local mascots are in `~/.local/share/dotfiles/mascots`.

An agent's model and effort are its own settings, which the home switch writes
from `modules/home/agents.nix`. `ws` starts an agent with no flags of its own,
and only reads those settings for `ws agent`.

Outside its own files, `ws project` writes the agents' trust for a project it
made: `hasTrustDialogAccepted` in `~/.claude.json`, under the lock Claude Code
takes on that file, `trust_level` in `~/.codex/config.toml`, and
`trustedWorkspaces` in `~/.gemini/antigravity-cli/settings.json`. Each write
reads the file and swaps the whole new file in.

## Rules

- Each file has one writer, which swaps it in whole. Only the `--watch` job
  fetches the inbox, and the Inbox popup asks it to with a signal.
- Anything `ws` must track itself is a named type that lists its states, with
  one function that moves between them. Never spread flags across the code to
  stand for a state.
- A load reads the multiplexer once, with `Snapshot`, and never asks it about
  one row at a time.
- A new fact about sessions or panes goes into both backends' `Snapshot`. A
  backend that can't know it leaves the field empty, and a status Open.
- Tests guard what a popup author or a person relies on, through the packages'
  public API: what Load, Fetch and the actions receive, what Esc does, the order
  Match ranks in. They never assert on private fields or rendered text.
- A new feature states its cost in lines in its commit message.
- Delete a feature nobody uses, rather than keep it working.

## Checking a change

Check a change with `go vet ./...`, `gofmt -l .` and `go test ./...`, then build
it from the repository root with `nix build .#ws`. Try a popup in a scratch Rex
session or a `tmux -L` server, never your working ones.
