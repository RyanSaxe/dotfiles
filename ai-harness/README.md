# AI harness

Global instructions, references, skills and hook scripts for Claude Code and
Codex. `modules/home/agents.nix` puts them where each agent looks. Most are
links into this checkout, so an edit applies at the agent's next session.

On a Mac, Claude Code comes from its own installer and Codex from the
Homebrew cask a Mac switch installs, and both update themselves. On Linux,
the home switch installs Codex from nixpkgs, and Claude Code too on a
computer with the `personal` role.

```text
ai-harness/
├── AGENTS.md         global instructions
├── references/       documentation AGENTS.md links to
├── skills/           Agent Skills: worktrees
├── tools/            notify-pushover.zsh, the agents' push hook, and
│                     link-agent-skills.sh, which shares Codex's skills
│                     with Claude Code
├── statusline.js     Claude Code's status line
└── codex/            requirements.toml, Codex's managed hooks
```

| Where the agent looks                                      | What's there                                              |
| ---------------------------------------------------------- | --------------------------------------------------------- |
| `~/.claude/CLAUDE.md`                                      | Two imports: `AGENTS.md` here and `~/.codex/AGENTS.md`    |
| `developer_instructions` in `~/.codex/config.toml`         | The text of `AGENTS.md`, copied at each home switch       |
| `~/.codex/AGENTS.md`                                       | Yours. A switch only creates it, empty, when it's missing |
| `~/.claude/references`, `~/.codex/references`              | Links to `references/`                                    |
| `~/.claude/skills/worktrees`, `~/.agents/skills/worktrees` | Links to `skills/worktrees`                               |
| `~/.claude/statusline.js`                                  | A link to `statusline.js`                                 |
| `/etc/codex/requirements.toml`                             | A copy of `codex/requirements.toml`                       |
| `/etc/codex/hooks/notify-pushover.zsh`                     | A link to `tools/notify-pushover.zsh`                     |

Claude reads your instructions live through the import. Codex has no import,
so it gets them at the next `home-switch`, and it reads them together with
`~/.codex/AGENTS.md`.

A Mac switch writes `/etc/codex`, where Codex reads its managed hooks. Home
Manager can't write to `/etc`, so on Linux the home switch puts the same
files in `~/.config/codex/managed`, and `/etc/codex` is a link to that
folder, made once by hand. `modules/codex-managed.nix` lists the files for
both.

Other tools install the rest of the skills. pair's comes from pair's own
`npx skills add RyanSaxe/pair -g`, which each home switch runs when the
skill is missing. byor and Rex install their own. Some installers write
skills only into `~/.agents/skills`, which only Codex reads, so on
computers with the `personal` role `tools/link-agent-skills.sh` links each
one into `~/.claude/skills`. Each home switch runs it once, and on a Mac a
launchd agent also runs it whenever `~/.agents/skills` changes.

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
