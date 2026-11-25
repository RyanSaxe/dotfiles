# ws

`ws` opens folders, worktrees and pull requests in Rex or tmux sessions and
tabs, and renders fuzzy popups for switching, diffs, GitHub reviews and vault
tasks. Run `ws --help` for all commands or `ws COMMAND --help` for flags and
examples.

## Commands

```sh
ws open ~/generic/dotfiles          # open a folder, or jump to its tab or session
ws tab . -- htop                    # run htop in a new tab of this folder's place
ws new fix-login                    # create ~/worktrees/PROJECT/fix-login + branch + agent
ws new fix-popups --session         # open as its own session instead of a tab
ws new fix-login --agent codex --prompt "Fix the redirect" --base main
ws pr 123                           # create a worktree on PR 123 with an agent
ws pr 123 --prompt "Review it"      # start the agent with a prompt
ws pr 123 --layout review           # open PR 123 in Neovim instead
ws project notes --in ~/Projects    # create a new git repo and open it
ws project junegunn/fzf.vim         # clone beside the owner's other repos and open it
ws ls                               # list worktrees and their agents
ws rm fix-login                     # close its tab/session, remove worktree, delete branch
ws agent                            # print the default agent, model and effort
```

Without `--force`, `ws rm` refuses dirty worktrees and keeps unmerged branches.
Outside Rex and tmux, `ws new`, `ws pr` and `ws project` create the directory
and print its path.

## Places

A folder's **place** is a session named `PARENT/FOLDER` (or `FOLDER` directly
under `~`), or for a worktree, a tab named `PROJECT/NAME` in any session. `ws`
discovers places live by name (including manual sessions) without storing a
mapping.

Worktrees open according to `dotfiles.ws.openAs` (`tab` by default):

- **`tab`:** a tab named `PROJECT/NAME` inside the project's session
  (`PARENT/PROJECT` or `PROJECT`). If that session is not running, `ws` starts
  it with a plain shell in the main checkout first so no unwanted agent starts.
- **`session`:** its own session named `PROJECT/NAME`.

Pass `--tab` or `--session` to `ws open`, `ws new` or `ws pr` to override once.
Main checkouts and plain folders always open as sessions. Extra tabs `ws` adds
for a worktree (such as files opened from the Files popup) share its name and
belong to its place; custom tabs (such as `tests`) belong to the session's
place.

`ws tab DIR -- COMMAND` runs `COMMAND` in a new tab of `DIR`'s place that closes
on exit. If `DIR` has no place yet, it opens one with `COMMAND` typed into a
persistent shell. The Files popup and `pair spawn` both use `ws tab`, so spawned
agents join their worktree's place.

`ws rm` and `Ctrl-X` in the Go popup close a place's tabs, or the whole session
if nothing else remains. Removing a worktree closes its tab and keeps the
project session open.

## Settings

Configure `dotfiles.ws` in the host file (`home-switch` writes
`~/.config/ws/config.toml`):

```nix
dotfiles.ws = {
  agent = "claude"; # claude, codex or agy (defaults to claude on personal, codex otherwise)
  openAs = "tab";   # tab or session (open_as in TOML)
};
```

`ws` launches the agent without hardcoded flags, so model and effort come from
the agent's own config:

| Agent       | Config file                             | Keys                              |
| ----------- | --------------------------------------- | --------------------------------- |
| Claude Code | `~/.claude/settings.json`               | `model`, `effortLevel`            |
| Codex       | `~/.codex/config.toml`                  | `model`, `model_reasoning_effort` |
| Antigravity | `~/.gemini/antigravity-cli/settings.json` | `model` (including effort suffix) |

`ws agent` prints the active values. Override per session with `--agent` or
extra flags after `--`:

```sh
ws agent                            # agent claude, model opus[1m], effort medium
ws new fix-popups -- --effort high  # runs claude --effort high
ws new fix-login --agent codex      # runs codex instead
```

In the Go popup's Worktrees tab, `Ctrl-T` creates a worktree for the current
project (or the selected row's project outside a repo), prompting for name,
optional agent/flags (such as `--model opus` or `codex -m gpt-6.1-sol`) and
prompt.

## New projects

`ws project` and `Ctrl-T` on Go → Folders accept a project name, `owner/repo` or
GitHub URL:

- **Existing repo:** clones into whichever folder under `~` holds the most repos
  from that owner (tie-broken by latest git activity), or simply opens an
  existing local clone.
- **New name:** runs `git init` and launches the agent with `"Set up this
  project"`, triggering the
  [project-setup](../ai-harness/skills/project-setup/SKILL.md) skill.

When the parent folder is ambiguous (new name or unknown owner), `Ctrl-T`
prompts with repo folders sorted by count, and `ws project` requires `--in DIR`.
`ws` aborts if the target directory or a matching session already exists.

`ws` pre-trusts new projects and clones from known owners so agents start
without trust prompts (`hasTrustDialogAccepted` in `~/.claude.json` under
Claude's lock, `trust_level = "trusted"` in `~/.codex/config.toml`, and
`trustedWorkspaces` in `~/.gemini/antigravity-cli/settings.json`). Clones from
new owners still prompt. Claude Code and Codex trust worktrees via their main
checkout; Antigravity trusts each path directly.

## Layouts

`--layout NAME` loads `~/.config/ws/layouts/NAME.toml`. The built-in default
`agent` layout is:

```toml
[[pane]]
run = "{agent} {prompt}"
focus = true

[[pane]]
split = "right"   # right, left, above or below
size = 35         # percent
```

Template variables for `run`: `{agent}` (CLI + flags), `{prompt}` (formatted per
agent: `-- PROMPT` for Claude Code/Codex, `-i PROMPT` for Antigravity, or empty),
`{pr}`, `{file}`, `{dir}` and `{name}`. Built-in layouts also include `review`
(`nvim gh://{pr}`) and `file` (`nvim {file}`, used by the Files popup).

## Popups

| Key          | Popup             | Lists                                                            |
| ------------ | ----------------- | ---------------------------------------------------------------- |
| Alt-O        | Go → Folders      | Repositories, worktrees and bookmarks, latest git activity first |
| Alt-W        | Go → Worktrees    | Every worktree, current project first, with branch and agent     |
| Alt-S        | Go → Sessions     | Every place (session or worktree tab) and its status             |
| Alt-A        | Go → Agents       | Running agents and status, newest report first                   |
| Ctrl-F in Go | Files             | Selected folder's files (plus hidden and ignored tabs)           |
| Alt-R        | Inbox → Needs you | GitHub PRs and issues needing your attention                     |
| Alt-T        | Inbox → Tasks     | Open vault tasks, soonest due first                              |
| Alt-C        | Theme             | Light/dark toggle and popup mascot                               |
| Alt-/        | Keys              | Every key binding and where it is configured                     |

Keys are bound in `config/rex/init.lua` (Rex) and `config/tmux/tmux.conf`
(tmux). In Rex, pressing another popup key switches popups immediately (`Alt-Shift-S`
opens Rex's own Change Session); tmux ignores popup keys while a popup is open.
Files opens over Go (`Esc` returns to Go). From a shell, `ws pick NAME` opens
any popup (`go`, `worktrees`, `sessions`, `agents`, `inbox`/`reviews`, `tasks`,
`files`); see `ws pick --help` for shared keys.

**Shared navigation:** type to filter (typing a project name on Worktrees floats
its worktrees to the top), arrows or `Ctrl-J`/`Ctrl-K` to move, `Tab`/`Shift-Tab`
to cycle tabs, `Ctrl-D`/`Ctrl-U` to scroll preview, `Ctrl-R` to refresh while
keeping current rows visible, and `Esc` to clear filter or close. Pressing
`Enter` before rows finish loading runs on the top match once it arrives unless
another key intervenes. A spinner marks tabs still loading.

**Shared actions** (the footer shows only keys valid for the active tab and row):

| Popup          | Enter  | Ctrl-T             | Ctrl-X | Ctrl-F | Ctrl-G | Ctrl-O       |
| -------------- | ------ | ------------------ | ------ | ------ | ------ | ------------ |
| Go → Folders   | go     | new project        | close  | files  |        |              |
| Go → Worktrees | go     | new worktree+agent | remove | files  | diff   | pull request |
| Go → Sessions  | go     |                    | close  | files  |        |              |
| Go → Agents    | go     |                    |        |        |        |              |
| Files          | edit   |                    |        |        |        |              |
| Inbox → Reviews | review | review with agent  | done   |        | diff   | browser      |
| Inbox → Tasks  | edit   | add                | done   |        |        |              |

- On Inbox review tabs, `Ctrl-T` and `Ctrl-G` apply to PRs only and `Ctrl-X`
  applies to Needs you only. On Go → Folders, `Ctrl-X` applies to open places
  and prompts for `y` confirmation before stopping running agents.
- On Go → Worktrees, `Ctrl-G` diffs tracked changes against `origin/HEAD` in
  `delta` (set it with `git remote set-head origin --auto` if missing), and
  `Ctrl-O` opens the branch's PR on `origin` (for fork PRs, use Inbox `Ctrl-O`).
- Bookmarks live in `~/.config/ws/bookmarks` (one path per line). Open folders
  show a `tab` or `session` tag. `Enter` in Files opens Neovim in a new tab of
  the folder's place (or starts it with the `file` layout).

## Agents that need you

An agent needs attention when it failed, is blocked or finished since you last
viewed its pane. Sketchybar's `A` lights **red** (failed), **peach** (blocked)
or **green** (done only). `Cmd-Alt-A` (`ws focus agent`) cycles within the
highest active urgency level (failed → blocked → done, oldest first), or across
all agents when none need you.

`ws` reads each multiplexer's native tracking:

- **tmux:** detects Claude Code, Codex, Antigravity, `pi` and Copilot CLI in the
  process table. A window bell while no client views that window marks the agent
  blocked (peach), because a bell cannot distinguish waiting from done; see
  [ai-harness/README.md](../ai-harness/README.md#agents-that-need-you). Go →
  Agents shows `working` while the window outputs and `idle` otherwise. Because
  tmux tracks bells and output per window, adjacent shell panes in the same
  window share those signals.
- **Rex:** a blocked agent needs you until its status changes; a failed or done
  agent needs you until a Rex window shows its pane. `ws attention --watch`
  records failed/done reports seen while focused so looking away does not
  re-trigger them.

## Inbox

Inbox gathers off-terminal items in one popup: GitHub review tabs first (`Alt-R`
opens **Needs you**), then vault task tabs (`Alt-T` opens the first **Tasks**
tab).

### Reviews

**Needs you** orders waiting GitHub items by urgency (tasks never appear here):

| Tag        | Reason                                                  |
| ---------- | ------------------------------------------------------- |
| `failing`  | A check failed on your PR                               |
| `changes`  | A review requested changes on your PR                   |
| `reviewed` | Someone reviewed your PR                                |
| `comment`  | Someone commented after your last reply or reaction     |
| `new`      | Opened this week in a watched repo (`attention-watch`)  |

**Pull requests**, **Issues** and **Watching** list your own open items and
activity in `attention-watch` repos. Accounts matching the host's
`attention-ignore` secret (logins or `*` globs, such as `*[bot]`) are excluded
from Inbox and sketchybar's `R`:

```text
release-robot
*[bot]
```

`Enter` checks out a PR in Neovim or opens an issue in the browser; `Ctrl-T`
checks out a PR and starts a review agent in a second tab. Opening an item keeps
it in **Needs you** until `Ctrl-X` marks it done (until new activity arrives).
`ws attention --watch` (a launchd agent on macOS) refreshes GitHub data every
five minutes; `Ctrl-R` refreshes immediately.

### Tasks

A task is any `- [ ]` line in Markdown under `$VAULT_DIR`, with an optional
`📅 YYYY-MM-DD` due date anywhere in a wrapped item (ending at a blank line,
list item, heading, quote, table or code fence):

```markdown
- [ ] Renew the domain before it lapses, and tell the team which registrar
      holds it 📅 2026-12-01
```

Tasks are tagged `overdue`, `today` or `soon` (within a week). Outside a repo,
one **Tasks** tab lists all open tasks. Inside a repo with an `origin` remote
(`PROJECT`), two tabs appear: **Project tasks** (`notes/projects/PROJECT/` and
`private/notes/projects/PROJECT/`) and **All tasks**.

- `Ctrl-T` prompts for task text and due date (`fri`, `3d`, `tmr`, `2026-12-01`)
  and appends to `notes/projects/PROJECT/TODO.md`.
- `Ctrl-X` checks off the box in the note.
- `Enter` opens the note at that line in Neovim inside the matching project's
  place (most recently active checkout matching `notes/projects/NAME`), or the
  vault's place if no project checkout exists.

If the host file sets no `vault`, `$VAULT_DIR` is unset, the Tasks tab reports
no vault and sketchybar's `T` stays off.

## What ws keeps

`ws` queries git, Rex, tmux and `gh` live. Its own state lives under
`~/.local/state/ws`; see [pkgs/ws/AGENTS.md](../pkgs/ws/AGENTS.md#what-ws-keeps).
