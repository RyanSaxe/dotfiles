# ws

`ws` opens folders, worktrees and pull requests as Rex or tmux sessions,
and draws the popups you use to switch between them. `ws --help` lists every
command and flag.

## Commands

```sh
ws open ~/generic/dotfiles          # open a folder as a session, or switch to it
ws new fix-login                    # make ~/worktrees/PROJECT/fix-login on its own branch, with an agent
ws new fix-login --agent codex --prompt "Fix the redirect" --base main
ws pr 123                           # make a worktree on pull request 123, with an agent
ws pr 123 --layout review           # open pull request 123 in Neovim instead
ws send fix-login "Run the tests"   # type a line and Enter into its agent
ws ls                               # list worktrees and their agents
ws rm fix-login                     # close its session, remove it and delete its branch
ws agent codex                      # start codex by default on this computer
```

Without `--force`, `ws rm` refuses a worktree with uncommitted changes, and
keeps a branch that hasn't merged. Outside Rex and tmux, `ws new` and
`ws pr` only make the worktree and print its path.

## Layouts

A layout is the panes a new session opens with. `--layout NAME` reads
`~/.config/ws/layouts/NAME.toml`, and `agent`, the default, is built in:

```toml
[[pane]]
run = "{agent} {prompt}"
focus = true

[[pane]]
split = "right"   # right, left, above or below
size = 35         # percent of the space
```

`run` can use `{agent}`, `{prompt}`, `{pr}`, `{dir}` and `{name}`. The
built-in `review` layout runs `nvim gh://{pr}`.

## Popups

| Key       | Popup     | Lists                                                                  |
| --------- | --------- | ---------------------------------------------------------------------- |
| Alt-O     | go        | Sessions, then repositories, latest git activity first, then bookmarks |
| Alt-W     | worktrees | This project's worktrees, and all of them on a second tab              |
| Alt-R     | reviews   | Pull requests and issues on GitHub that involve you                    |
| Alt-T     | tasks     | Open tasks in the vault, soonest due first                             |
| Alt-A     | agents    | Rex terminals whose program reports a status                           |
| Alt-C     | theme     | Light or dark, and the mascot                                          |
| Alt-/     | keys      | Every key binding, and where it is set                                 |

Rex binds these in `config/rex/init.lua`, and tmux in
`config/tmux/tmux.conf`. The agents popup works only in Rex. `ws pick NAME`
opens any of them from a shell.

In every popup, typing filters the list, the arrows or Ctrl-J and Ctrl-K
move, Tab switches tabs, Enter acts on the row and Esc clears the filter or
closes. The bottom line lists the popup's other keys.

| Popup     | Enter  | Ctrl-T                 | Ctrl-X        | Other                            |
| --------- | ------ | ---------------------- | ------------- | -------------------------------- |
| go        | go     |                        | close session | Ctrl-F search the folder's files |
| worktrees | go     | new worktree and agent | remove        |                                  |
| reviews   | review | review with an agent   | done          | Ctrl-G diff, Ctrl-O browser      |
| tasks     | edit   | add                    | done          |                                  |

The go popup's bookmarks are the folders in `~/.config/ws/bookmarks`, one
per line.

## Reviews

The Needs you tab lists what waits on you, most urgent first:

| Tag        | Why                                                   |
| ---------- | ----------------------------------------------------- |
| `failing`  | A check failed on your pull request                   |
| `changes`  | A review asked for changes on your pull request       |
| `reviewed` | Someone else reviewed your pull request               |
| `comment`  | Someone wrote after your last reply or reaction       |
| `new`      | Someone opened it this week in a repository you watch |

Pull requests and Issues list your own open ones, and Watching lists what
is new in the repositories you watch. Each computer's watched repositories
are its `attention-watch` secret.

Enter checks a pull request out into its own worktree and opens it in
Neovim. On an issue, it opens the browser. Ctrl-T does the same as Enter
and also starts an agent in a second tab, asked to review the pull
request. On Needs you, Ctrl-X marks an item done until something new
happens on it.

Reviews reads the inbox that `ws attention --watch` fetches from GitHub
every five minutes, so it opens without waiting on GitHub. On a Mac, that
job runs as a launchd agent. Ctrl-R fetches now.

## Tasks

A task is a `- [ ]` line in any Markdown file under `$VAULT_DIR`, which is
`~/generic/vault`. A date after 📅 makes it due:

```markdown
- [ ] Renew the domain 📅 2026-12-01
```

Tasks tags each one `overdue`, `today` or `soon`, for a date within a week.
In a repository with an `origin` remote, PROJECT is the remote's
repository name, and the first tab lists the tasks under
`notes/projects/PROJECT/` and `private/notes/projects/PROJECT/`. Ctrl-T
asks for the text and a due date, such as `fri`, `3d`, `tmr` or
`2026-12-01`, and adds the task to `notes/projects/PROJECT/TODO.md`.
Ctrl-X ticks the box in the note.

## What ws keeps

`ws` asks git, Rex, tmux and gh for their state each time. What it keeps
itself is in `~/.local/state/ws`, and
[pkgs/ws/AGENTS.md](../pkgs/ws/AGENTS.md#what-ws-keeps) lists each file.
