# AI harness

Global instructions, skills and hook scripts for Claude Code and Codex.
`modules/home/agents.nix` puts them where each agent looks. Most are links
into this checkout, so an edit applies at the agent's next session.

On a Mac, Claude Code comes from its own installer and Codex from the
Homebrew cask a Mac switch installs, and both update themselves. On Linux,
the home switch installs Codex from nixpkgs, and Claude Code too on a
computer with the `personal` role.

A computer without Claude Code sets `dotfiles.claudeCode = false` in its
host file. Its switches then write nothing for Claude Code: no
`~/.claude` files or settings, no skills or agents linked for it, and no
Claude Code theme or status line colors.

```text
ai-harness/
├── AGENTS.md         global instructions
├── references/       what AGENTS.md says to read before writing code,
│                     tests or prose, or checking work
├── skills/           Agent Skills: worktrees, wiki and project-setup
├── tools/            notify-pushover.zsh, the agents' push hook,
│                     link-agent-skills.sh, which shares Codex's skills
│                     with Claude Code, and convert-codex-agents.py,
│                     which does the same for Codex's agents
├── statusline.js     Claude Code's status line
└── codex/            requirements.toml, Codex's managed hooks
```

| Where the agent looks                              | What's there                                        |
| -------------------------------------------------- | --------------------------------------------------- |
| `~/.claude/CLAUDE.md`                              | An import of `AGENTS.md`                            |
| `developer_instructions` in `~/.codex/config.toml` | The text of `AGENTS.md`, copied at each home switch |
| `~/.claude/skills/NAME`, `~/.agents/skills/NAME`   | Links to each skill in `skills/`                    |
| `~/.claude/statusline.js`                          | A link to `statusline.js`                           |
| `/etc/codex/requirements.toml`                     | A copy of `codex/requirements.toml`                 |
| `/etc/codex/hooks/notify-pushover.zsh`             | A link to `tools/notify-pushover.zsh`               |
| `/etc/codex/hooks/pair-register.sh`                | A link to `tools/pair-register.sh`                  |

Claude reads the instructions live through the import. Codex has no import,
so it gets them at the next `home-switch`.

A Mac switch writes `/etc/codex`, where Codex reads its managed hooks. Home
Manager can't write to `/etc`, so on Linux the home switch puts the same
files in `~/.config/codex/managed`, and `/etc/codex` is a link to that
folder, made once by hand. `modules/codex-managed.nix` lists the files for
both.

Most skills come from a private catalog, which installs them into
`~/.agents/skills`, the folder Codex reads. Claude Code reads only
`~/.claude/skills`, so on computers with the `personal` role
`tools/link-agent-skills.sh` links each skill there. Each home switch runs it
once, and on a Mac a launchd agent also runs it whenever `~/.agents/skills`
changes. The catalog's agents land only in `~/.codex/agents`, so
`tools/convert-codex-agents.py` writes a Claude agent in `~/.claude/agents`
for each one, at each home switch and, on a Mac, whenever that folder
changes. Other tools install their own skills: pair's comes from pair's own
`npx skills add RyanSaxe/pair -g`, which each home switch runs when the
skill is missing, and byor and Rex install theirs.

Computers with the `personal` role also get pi and Copilot CLI, two agents
besides Claude Code and Codex that pair's hub can wake. Both read pair's
skill from `~/.agents/skills`, as Codex does. Each home switch registers
pair's pi extension from `~/.nix-profile`, a path that stays the same when
pair updates. The `copilot` alias starts Copilot CLI with its UI server and
access to pair's state folder, which pair needs.

Each Claude Code, Codex and Copilot session registers with pair as it
starts, so `pair agents` lists it and other agents can message it. Each home
switch adds pair's hook to Claude Code's `SessionStart` list beside Rex's,
and writes `~/.copilot/hooks/pair.json` on computers with the `personal`
role. Codex runs `tools/pair-register.sh` as a managed hook.

Each agent's settings live in `modules/home/agents.nix`. Each home switch
merges them into `~/.claude/settings.json` and `~/.codex/config.toml`, keeping
whatever the agent wrote there itself. Deleting a setting from the module
leaves it in the file, so delete it there by hand too.

## Phone notifications

`tools/notify-pushover.zsh` sends a [Pushover](https://pushover.net) push when
an agent finishes a turn, asks for permission or a question, or fails. The
title names the project, the agent and the event, and the message is the
agent's last message or what it is asking for. Claude Code calls it from its
`Stop`, `Notification` and `StopFailure` hooks, and Codex from the managed
`Stop` and `PermissionRequest` hooks in `codex/requirements.toml`.

The script takes its two keys from the first place that has them:
`PUSHOVER_USER` and `PUSHOVER_TOKEN` in the environment, then
`pushover-user` and `pushover-token` in `~/.config/sops-nix/secrets`, which
each home switch decrypts from `secrets/secrets.yaml`, then the login
keychain. On macOS it sends nothing if the keyboard or mouse was used in the
last 60 seconds, and `PUSHOVER_IDLE` sets a different number of seconds. To
send a test push:

```sh
echo '{"hook_event_name": "Stop", "last_assistant_message": "test"}' |
  PUSHOVER_IDLE=0 ai-harness/tools/notify-pushover.zsh test
```

## Agents that need you

In tmux, `ws` learns that an agent needs you from its window's bell, as
[docs/ws.md](../docs/ws.md#agents-that-need-you) describes, so both agents
ring it. Each home switch sets Claude Code's `preferredNotifChannel` to
`terminal_bell`. On computers without Rex, it also sets Codex's
`tui.notification_method` to `bel`, `tui.notifications` to `true` and
`tui.notification_condition` to `always`, so Codex rings whether or not its
pane has focus. Rex computers keep Codex's own notifications.

When each agent rang, in a tmux session no client showed, with Claude Code
2.1.327 and Codex 0.169:

| Agent       | Finished turn                | Permission prompt or approval  | Question                       |
| ----------- | ---------------------------- | ------------------------------ | ------------------------------ |
| Claude Code | about a minute after it ends | about 6 seconds after it shows | about 6 seconds after it shows |
| Codex       | as it ends                   | as it shows                    | as it shows                    |

Claude Code rings for a finished turn only once its prompt has sat idle for
a minute, so a turn you watched end still needs you if you switch away
within that minute. A Codex plan-mode prompt rings with the turn it ends,
and a Codex `request_permissions` prompt rings nothing.
