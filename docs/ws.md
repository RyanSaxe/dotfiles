# ws

`ws` opens folders, worktrees and pull requests in Rex or tmux sessions and
tabs, and draws the popups you use to switch between them. `ws --help`
lists every command, and `ws COMMAND --help` lists the command's flags with
examples.

## Commands

```sh
ws open ~/generic/dotfiles          # open a folder, or switch to its tab or session
ws tab . -- htop                    # run htop in a new tab of this folder's tab or session
ws new fix-login                    # make ~/worktrees/PROJECT/fix-login on its own branch, with an agent
ws new fix-popups --session         # open it as a session of its own, not a tab
ws new fix-login --agent codex --prompt "Fix the redirect" --base main
ws pr 123                           # make a worktree on pull request 123, with an agent
ws pr 123 --prompt "Review it"      # start its agent with a prompt, as ws new does
ws pr 123 --layout review           # open pull request 123 in Neovim instead
ws project notes --in ~/Projects    # make a new project with git init, and open it
ws project junegunn/fzf.vim         # clone a repository next to its owner's others, and open it
ws ls                               # list worktrees and their agents
ws rm fix-login                     # close its tab or session, remove it and delete its branch
ws agent                            # print the agent ws starts, with its model and effort
```

Without `--force`, `ws rm` refuses a worktree with uncommitted changes, and
keeps a branch that hasn't merged. Outside Rex and tmux, `ws new`, `ws pr`
and `ws project` only make the worktree or project and print its path.

## Places

A folder's terminals are in its place: a session labeled after the folder,
or, for a worktree, a tab named PROJECT/NAME in any session. `ws` finds a
place by that name wherever it is, in sessions you made by hand too, and
keeps no record of where it put one.

A worktree opens where the host file's `openAs` says, `tab` by default:

- **tab:** a tab named PROJECT/NAME in the project's session, labeled
  PROJECT. When that session isn't running, `ws` starts it with a plain
  shell in the main checkout as its first tab, so no agent starts that
  nobody asked for.
- **session:** a session of its own, labeled PROJECT/NAME.

`--tab` and `--session` on `ws open`, `ws new` and `ws pr` override it for
one command. Any other folder, such as a main checkout, opens as a session
of its own. A tab `ws` adds to a worktree's tab, such as a file the files
popup opens, takes the worktree's name, so it is part of the place. Any
other tab, such as one you or an agent named `tests`, is part of its
session's place.

`ws tab DIR -- COMMAND` runs COMMAND in a new tab of DIR's place, which
closes when COMMAND exits. When DIR has no place, it opens one first, with
COMMAND typed into its shell, which stays open after COMMAND exits. The
files popup opens a file the same way, and `pair spawn` opens each agent
it starts with `ws tab`, so an agent spawned in a worktree joins that
worktree's place.

`ws rm` and Ctrl-X in the go popup close a place's tabs, or its whole
session when nothing else is in it. Removing a worktree closes its tab and
leaves the project's session open.

## Settings

Each computer's host file sets ws's settings under `dotfiles.ws`, and
`home-switch` writes them to `~/.config/ws/config.toml`. `agent` is the
agent CLI ws starts, claude or codex. It defaults to claude on a computer
with Claude Code and to codex otherwise. `openAs`, `open_as` in the TOML,
is where a worktree opens, `tab` or `session`, as [Places](#places) says:

```nix
dotfiles.ws = {
  agent = "claude";
  openAs = "tab";
};
```

ws starts the agent with no flags of its own, so its model and effort are
the agent's own settings, which every session of it shares and
`modules/home/agents.nix` sets: `model` and `effortLevel` in
`~/.claude/settings.json` for Claude Code, and `model` and
`model_reasoning_effort` in `~/.codex/config.toml` for Codex. `ws agent`
prints them. `ws new` and `ws pr` pass the words after `--` to the agent,
which override its settings for that session:

```sh
ws agent                            # agent claude, model opus[1m], effort medium
ws new fix-popups -- --effort high  # starts claude --effort high
ws new fix-login --agent codex      # starts codex instead
```

Ctrl-T on the go popup's Worktrees tab makes a worktree of the project you're
in, as `ws new` does, whichever row is selected. Outside a project, it uses
the selected row's project. It asks for the worktree's name, then an agent,
flags or both, such as `--model opus` or `codex -m gpt-6.1-sol`, then a
prompt.

## New projects

`ws project` and Ctrl-T on the go popup's Folders tab take a new project's
name, `owner/repo` or a GitHub URL, and open the project as Enter does:

- **A repository** goes in the folder under your home folder that holds most
  of its owner's repositories. On a tie, the folder with the owner's latest
  git activity wins. A repository already on this computer only opens.
- **A new name** becomes a folder with `git init`, and its agent starts with
  the prompt "Set up this project", which loads the
  [project-setup](../ai-harness/skills/project-setup/SKILL.md) skill.

For a new name, or an owner with no repositories here, ws can't tell where
the project goes. Ctrl-T then asks, offering the folders under your home
folder that hold repositories, the one with the most first, and
`ws project` needs `--in DIR`. When anything else already has the project's
folder, or a session of its name is running, ws stops before it makes
anything.

ws trusts a new project, and a clone from an owner with repositories here,
so its agent starts without asking. It sets `hasTrustDialogAccepted` in
`~/.claude.json`, under the lock Claude Code takes on that file, and
`trust_level = "trusted"` in `~/.codex/config.toml`. A clone from an owner
with nothing here still asks. A worktree needs nothing, since both CLIs
trust it through its main checkout.

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

`run` can use `{agent}`, `{prompt}`, `{pr}`, `{file}`, `{dir}` and
`{name}`. `{agent}` is the agent and its flags, and the `--` after it keeps
a flag that takes several values, such as claude's `--add-dir`, from taking
the prompt as one of them. The built-in `review` layout runs
`nvim gh://{pr}`, and the built-in `file` layout runs `nvim {file}`, which
the files popup starts a folder's session with.

## Popups

| Key          | Popup            | Lists                                                                |
| ------------ | ---------------- | -------------------------------------------------------------------- |
| Alt-O        | go, on Folders   | Repositories, worktrees and bookmarks, latest git activity first     |
| Alt-W        | go, on Worktrees | Every worktree, this project's first, with its branch and agent      |
| Alt-S        | go, on Sessions  | Each place, a session or a worktree's tab, and what it's doing       |
| Alt-A        | go, on Agents    | Agents and what each is doing, the latest report first               |
| Ctrl-F in go | files            | The selected folder's files, and its hidden and ignored ones on tabs |
| Alt-R        | inbox, on Needs  | Pull requests and issues on GitHub that involve you                  |
| Alt-T        | inbox, on Tasks  | Open tasks in the vault, soonest due first                           |
| Alt-C        | theme            | Light or dark, and the mascot                                        |
| Alt-/        | keys             | Every key binding, and where it is set                               |

Tab moves between the go popup's four tabs, and between the Inbox's: Needs
you, Pull requests, Issues and Watching, then the Tasks tabs. Typing a
project's name on Worktrees brings that project's worktrees to the top.

Rex binds the Alt keys in `config/rex/init.lua`, and tmux in
`config/tmux/tmux.conf`. In Rex, one of them pressed inside a popup
replaces that popup, and in tmux the popup ignores it. Files opens over the
go popup, and Esc goes back to it. `ws pick NAME` opens any of these
popups from a shell, where `go`, `worktrees`, `sessions` and `agents` open
the go popup on their tab. `inbox` and `reviews` open the Inbox on Needs
you, and `tasks` opens it on its first Tasks tab. `ws pick files` lists the
files of the folder it runs in. `ws pick --help` lists the keys every popup shares.

In every popup, typing filters the list, the arrows or Ctrl-J and Ctrl-K
move, Tab and Shift-Tab move forward and back through the tabs, Ctrl-D and
Ctrl-U scroll the details, Ctrl-R gets fresh data and Esc clears the filter
or closes. Enter pressed before the rows appear acts on the top match once
they do, unless another key comes first.

A popup loads the tab it opens on first, and shows rows as they come in. While
a tab is still loading, a spinner sits beside its count and beside the
filter's count, since more rows can still arrive. Ctrl-R keeps the rows on
screen until the new ones are complete.

Each other key means the same in every popup that has it. Enter goes to or
opens the row, Ctrl-T starts something new, Ctrl-X finishes or removes the
row, Ctrl-F searches the row's folder, Ctrl-G shows a diff and Ctrl-O opens
the browser.

| Popup          | Enter  | Ctrl-T                 | Ctrl-X | Ctrl-F | Ctrl-G | Ctrl-O       |
| -------------- | ------ | ---------------------- | ------ | ------ | ------ | ------------ |
| go, Folders    | go     | new project            | close  | files  |        |              |
| go, Worktrees  | go     | new worktree and agent | remove | files  | diff   | pull request |
| go, Sessions   | go     |                        | close  | files  |        |              |
| go, Agents     | go     |                        |        |        |        |              |
| files          | edit   |                        |        |        |        |              |
| inbox, reviews | review | review with an agent   | done   |        | diff   | browser      |
| inbox, Tasks   | edit   | add                    | done   |        |        |              |

The bottom line lists only the keys that work on the tab and the selected
row, and a key that doesn't work there does nothing. The Inbox's reviews
tabs, the ones before Tasks, offer Ctrl-T and Ctrl-G only on a pull request
and Ctrl-X only on Needs you, and the go popup's Folders tab offers Ctrl-X
only on a folder that is open.

On the Worktrees tab, Ctrl-G shows in `delta` how the files git tracks
changed, committed or not, since the branch left the project's default
branch, the one `origin/HEAD` names. A project without `origin/HEAD` has no
Ctrl-G, and `git remote set-head origin --auto` sets it. Ctrl-O opens the
open pull request from the branch on `origin`. A fork's pull request from a
branch of the same name doesn't count, so a worktree of someone else's pull
request has no Ctrl-O, and the Inbox's Ctrl-O opens it instead.

The go popup's bookmarks are the folders in `~/.config/ws/bookmarks`, one
per line. A folder that is open is tagged `tab` or `session`, by its
place, and Enter on it goes there. Ctrl-X asks before it closes the place,
and closes it only when you answer `y`, since the agent in it stops too.
Enter in files opens the file in Neovim, in a new tab of the folder's
place, or starts that place with the `file` layout.
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
  orders those agents by how long they have needed you. The go popup's
  Agents tab shows the agent as working while its window prints and idle
  otherwise.
  tmux tracks bells and output per window, so a bell or output from a shell
  pane beside the agent counts as the agent's.
- **Rex:** a blocked or failed agent needs you until it reports something
  else, and a done one until a Rex app shows its pane. The pane you're
  looking at needs nothing, and `ws attention --watch` remembers a done
  report that came while you looked, so it doesn't need you once you look
  away.

## Inbox

The Inbox is one popup for what waits on you outside the terminal. Its
first tabs are reviews, the pull requests and issues on GitHub that involve
you, and its last tabs are the vault's open tasks. Alt-R opens it on Needs
you and Alt-T on its first Tasks tab, and Tab moves through them all. Each
tab keeps its own keys.

### Reviews

The Needs you tab lists the reviews that wait on you, most urgent first.
It never lists a task:

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

The Inbox skips the accounts in each computer's `attention-ignore` secret:
the pull requests and issues they open, and their comments and reviews on
the rest, so nothing they do needs you or lights sketchybar's R. Each line
is a GitHub login, or a pattern where `*` stands for any text. An app's
login ends in `[bot]`, so `*[bot]` skips every app:

```text
release-robot
*[bot]
```

Enter checks a pull request out into its own worktree and opens it in
Neovim, or opens an issue in the browser. Ctrl-T opens a pull request as
Enter does and also starts an agent in a second tab, asked to review it.
Opening an item leaves it on Needs you, and only Ctrl-X there marks it done
until something new happens on it.

These tabs read what `ws attention --watch` fetches from GitHub every five
minutes, so the Inbox opens without waiting on GitHub. On a Mac, that job
runs as a launchd agent. Ctrl-R on one of them fetches now.

### Tasks

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

The Tasks tabs come last and tag each task `overdue`, `today` or `soon`,
for a date within a week. Outside a repository there is one, named Tasks,
with every open task. In a repository with an `origin` remote, PROJECT is
the remote's repository name, and there are two: Project tasks lists the
tasks under `notes/projects/PROJECT/` and
`private/notes/projects/PROJECT/`, and All tasks lists every open task. Ctrl-T
asks for the text and a due date, such as `fri`, `3d`, `tmr` or
`2026-12-01`, and adds the task to `notes/projects/PROJECT/TODO.md`.
Ctrl-X ticks the box in the note.

On a computer whose host file sets no vault, `$VAULT_DIR` is unset, so
the Tasks tab says the vault isn't set up and the T letter stays off.

## What ws keeps

`ws` asks git, Rex, tmux and gh for their state each time. What it keeps
itself is in `~/.local/state/ws`, and
[pkgs/ws/AGENTS.md](../pkgs/ws/AGENTS.md#what-ws-keeps) lists each file.
