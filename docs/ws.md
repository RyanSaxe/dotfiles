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
ws ls                               # list worktrees and their agents
ws rm fix-login                     # close its session, remove it and delete its branch
ws agent codex                      # start codex by default on this computer
```

Without `--force`, `ws rm` refuses a worktree with uncommitted changes, and
keeps a branch that hasn't merged. Outside Rex and tmux, `ws new` and
`ws pr` only make the worktree and print its path.

Each agent has its own default flags, which every agent ws starts gets.
`ws new` replaces them with the words after `--`:

```sh
ws agent claude --effort medium     # claude starts with --effort medium, and is the default
ws new fix-login                    # starts claude --effort medium
ws new fix-popups -- --model opus   # starts claude --model opus
ws agent claude --                  # clears claude's default flags
```

The worktrees popup's Ctrl-T asks for an agent, flags or both, such as
`--model opus` or `codex -c model_reasoning_effort=high`.

## Layouts

A layout is the panes a new session opens with. `--layout NAME` reads
`~/.config/ws/layouts/NAME.toml`, and `agent`, the default, is built in:

```toml
[[pane]]
run = "{agent} -- {prompt}"
focus = true

[[pane]]
split = "right"   # right, left, above or below
size = 35         # percent of the space
```

`run` can use `{agent}`, `{prompt}`, `{pr}`, `{dir}` and `{name}`.
`{agent}` is the agent and its flags, and the `--` after it keeps a flag
that takes several values, such as claude's `--add-dir`, from taking the
prompt as one of them. The built-in `review` layout runs `nvim gh://{pr}`.

## Popups

| Key       | Popup     | Lists                                                                  |
| --------- | --------- | ---------------------------------------------------------------------- |
| Alt-O     | go        | Repositories, worktrees and bookmarks, latest git activity first       |
| Alt-S     | sessions  | Running sessions and what each is doing, on the go popup's second tab  |
| Alt-W     | worktrees | This project's worktrees, and all of them on a second tab              |
| Alt-R     | reviews   | Pull requests and issues on GitHub that involve you                    |
| Alt-T     | tasks     | Open tasks in the vault, soonest due first                             |
| Alt-A     | agents    | Agents and what each is doing                                          |
| Alt-C     | theme     | Light or dark, and the mascot                                          |
| Alt-/     | keys      | Every key binding, and where it is set                                 |

Rex binds these in `config/rex/init.lua`, and tmux in
`config/tmux/tmux.conf`. In Rex, one of these keys pressed inside a popup
replaces that popup, and in tmux the popup ignores it. `ws pick NAME`
opens any of them from a shell.

In every popup, typing filters the list, the arrows or Ctrl-J and Ctrl-K
move, Tab and Shift-Tab move forward and back through the tabs, Enter acts
on the row and Esc clears the filter or closes. Enter pressed before the
rows appear acts on the top match once they do, unless another key comes
first. The bottom line lists the popup's other keys.

| Popup     | Enter  | Ctrl-T                 | Ctrl-X        | Other                            |
| --------- | ------ | ---------------------- | ------------- | -------------------------------- |
| go        | go     |                        | close session | Ctrl-F search the folder's files |
| worktrees | go     | new worktree and agent | remove        |                                  |
| reviews   | review | review with an agent   | done          | Ctrl-G diff, Ctrl-O browser      |
| tasks     | edit   | add                    | done          |                                  |

The go popup's bookmarks are the folders in `~/.config/ws/bookmarks`, one
per line. A folder that has a running session is tagged `session`, and
Enter on it goes to that session.
In Rex, Alt-Shift-S opens Rex's own Change Session.

## Agents that need you

An agent needs you when it finished or waits on you and you haven't
looked at its pane since. Sketchybar's A lights while one does: red when
an agent has failed, peach when one is blocked, and green when the agents
that need you have only finished. Cmd-Alt-A (`ws focus agent`) cycles
through those agents, failed first, then blocked, then done, and within
each the one that has needed you longest first. When no agent needs you,
it cycles through every agent. `ws` reads what each multiplexer already
tracks:

- **tmux:** an agent is a pane where Claude Code, Codex, pi, Copilot CLI or
  opencode runs, however it started. `ws` finds those programs in the
  process table each time it looks. An agent needs you once its
  window's bell rings while no client shows the window, until a client
  switches to it, so a bell you saw marks nothing. Claude Code and Codex
  ring the bell when they finish or wait, as
  [ai-harness/README.md](../ai-harness/README.md#agents-that-need-you)
  describes. A bell doesn't say whether the agent finished or waits, so an
  agent that rang counts as blocked: it lights the A peach, and Cmd-Alt-A
  orders those agents by how long they have needed you. The agents popup
  shows the agent as working while its window prints and idle otherwise.
  tmux tracks bells and output per window, so a bell or output from a shell
  pane beside the agent counts as the agent's.
- **Rex:** a blocked or failed agent needs you until it reports something
  else, and a done one until a Rex app shows its pane. The pane you're
  looking at needs nothing, and `ws attention --watch` remembers a done
  report that came while you looked, so it doesn't need you once you look
  away.

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

Reviews skips the accounts in each computer's `attention-ignore` secret:
the pull requests and issues they open, and their comments and reviews on
the rest, so nothing they do needs you or lights sketchybar's R. Each line
is a GitHub login, or a pattern where `*` stands for any text. An app's
login ends in `[bot]`, so `*[bot]` skips every app:

```text
release-robot
*[bot]
```

Enter checks a pull request out into its own worktree and opens it in
Neovim. On an issue, it opens the browser. Ctrl-T does the same as Enter
and also starts an agent in a second tab, asked to review the pull
request. On Needs you, Ctrl-X marks an item done until something new
happens on it.

Reviews reads the inbox that `ws attention --watch` fetches from GitHub
every five minutes, so it opens without waiting on GitHub. On a Mac, that
job runs as a launchd agent. Ctrl-R fetches now.

## Tasks

A task is a `- [ ]` line in any Markdown file under `$VAULT_DIR`, the
vault's folder, which the computer's host file sets. A date after 📅 makes
it due:

```markdown
- [ ] Renew the domain 📅 2026-12-01
```

A long task can wrap onto the lines below it, as rumdl wraps it. Its
text goes on until a blank line, a list item, a heading, a quote, a table
or a code fence, and the date can be on any of its lines:

```markdown
- [ ] Renew the domain before it lapses, and tell the team which registrar
      holds it 📅 2026-12-01
```

Tasks tags each one `overdue`, `today` or `soon`, for a date within a week.
In a repository with an `origin` remote, PROJECT is the remote's
repository name, and the first tab lists the tasks under
`notes/projects/PROJECT/` and `private/notes/projects/PROJECT/`. Ctrl-T
asks for the text and a due date, such as `fri`, `3d`, `tmr` or
`2026-12-01`, and adds the task to `notes/projects/PROJECT/TODO.md`.
Ctrl-X ticks the box in the note.

On a computer whose host file sets no vault, `$VAULT_DIR` is unset, so
Tasks says the vault isn't set up and the T letter stays off.

## What ws keeps

`ws` asks git, Rex, tmux and gh for their state each time. What it keeps
itself is in `~/.local/state/ws`, and
[pkgs/ws/AGENTS.md](../pkgs/ws/AGENTS.md#what-ws-keeps) lists each file.
