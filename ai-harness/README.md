# AI Harness

One home for global configuration shared by Claude Code, Codex CLI, and GitHub
Copilot CLI.

The three harnesses expose similar features through different files and
directories. This package keeps portable content in one place and isolates the
differences in small harness-specific directories. Files are linked or loaded
directly from the repository: there is no generated copy to synchronize.

## How it works

```text
ai-harness/
├── AGENTS.md                    global instructions
├── references/                 supporting documentation loaded on demand
├── skills/                     portable Agent Skills
├── tools/                      command-line tools for agents
├── statusline.js               shared Claude/Copilot status line
├── .claude-plugin/plugin.json  Claude Code plugin manifest
├── plugin.json                 Copilot CLI plugin manifest
├── claude/                     Claude Code settings and extensions
├── copilot/                    Copilot CLI settings and extensions
└── codex/                      Codex settings and extensions
```

Claude and Copilot load `ai-harness/` as a local plugin. Codex reads the same
instructions and skills through explicit links. The shell launchers select the
local plugin or Codex profile while preserving arguments passed by the user.

GNU Stow manages packages that map cleanly into one target tree. This package
does not: the same source directory is a plugin root, selected files belong
under `$HOME`, and Codex system configuration belongs under `/etc`. `install.sh`
therefore creates the small set of links directly. The existing `workmux/`
package continues to use Stow.

## Install

Run the repository installer from the dotfiles root:

```sh
./install.sh
# or, on an existing dotfiles installation:
./install.sh agents
```

The `agents` tier creates the links described below and configures the shell
launchers. Re-run it after changing the repository location. Edits to existing
files take effect immediately; additions under a linked directory need no
install step.

The Codex admin links under `/etc/codex` require `sudo`.

## Shared instructions

`AGENTS.md` is the source for global instructions in every harness.

| Harness | Link                                 |
| ------- | ------------------------------------ |
| Claude  | `~/.claude/CLAUDE.md`                |
| Copilot | `~/.copilot/copilot-instructions.md` |
| Codex   | `~/.codex/AGENTS.md`                 |

Each harness also receives a `references` link beside its instruction file, so
relative links from `AGENTS.md` resolve consistently. Project instructions
remain independent and take precedence through each harness's normal rules.

## Skills

Every direct child of `skills/` is one
[Agent Skill](https://agentskills.io/specification):

```text
skills/
└── explain-query/
    ├── SKILL.md
    ├── references/
    ├── examples/
    └── anything-else/
```

Only `SKILL.md` is required. It defines `name` and `description`; everything
else in the skill directory is unrestricted. Optional frontmatter is fine as
long as the skill does not depend on behavior missing from another harness.
Codex-specific metadata belongs in `agents/openai.yaml` inside the skill.

Claude and Copilot discover `skills/` through their local plugin. Codex uses:

```text
/etc/codex/skills -> ai-harness/skills
```

The Codex admin scope is separate from `~/.agents/skills`, so user-installed
skills remain in their native directory. Adding or editing a skill makes it
available to all three harnesses without relinking; a running session may need
to reload it.

## Harness configuration

Harness-specific files use the native format of each CLI.

| Harness | Settings                | Agents                           | Hooks                     |
| ------- | ----------------------- | -------------------------------- | ------------------------- |
| Claude  | `claude/settings.json`  | `claude/agents/<name>.md`        | `claude/hooks/hooks.json` |
| Copilot | `copilot/settings.json` | `copilot/agents/<name>.agent.md` | `copilot/hooks.json`      |
| Codex   | `codex/config.toml`     | `codex/agents/<name>.toml`       | inline in `config.toml`   |

Add Claude and Copilot agent or hook directories to their plugin manifests
when the first implementation is added. Codex agent files are linked
individually into `~/.codex/agents/`, allowing native additions to coexist.

Hook implementations shared by more than one harness belong in `tools/`;
registration remains harness-specific. Hooks from this repository run
alongside user, project, plugin, Workmux, and BYOR hooks.

### Settings and state

Stable preferences belong in the tracked settings files. State managed by a
harness or another application stays in its native home, including credentials,
sessions, caches, permissions, trust records, installed plugins, and downloaded
skills.

Claude receives its tracked settings with `--settings`; its native
`~/.claude/settings.json` remains available for Workmux and other hooks.
Copilot's `~/.copilot/settings.json` links to `copilot/settings.json`; changes
made through Copilot are ordinary dotfile changes. Codex reads `codex/config.toml` from its
system layer:

```text
/etc/codex/config.toml -> ai-harness/codex/config.toml
```

Codex launches with `--profile dotfiles`. The profile remains a regular file at
`~/.codex/dotfiles.config.toml`, where Codex can write user state without
changing tracked system defaults.

## Tools and references

`tools/` contains commands intended for agents across projects. Public commands
are linked individually into `~/.local/bin`; runtime output belongs under the
appropriate XDG state or cache directory.

`references/` contains focused documentation linked from `AGENTS.md` or a
skill. Unlinked references are not loaded automatically, which keeps the global
instruction file small.

## MCP, Workmux, and themes

Use a root `.mcp.json` only when Claude and Copilot can share the definition
unchanged. Otherwise keep MCP configuration under each harness directory.
Codex MCP servers live in `codex/config.toml`. Credentials always come from the
environment or a native credential store.

[Workmux](../workmux/dot-config/workmux/config.yaml) defines agent launch and
worktree behavior. Files installed by `workmux setup` stay in the harness's
native directories.

Theme and status-line integrations consume the generated colors in `../theme/`.
They do not define a second palette. Claude and Copilot call the shared
`statusline.js`; Codex uses its native status-line items and the generated
`dotfiles.tmTheme` in `~/.codex/themes`.

## Extending the harness

1. Put portable content in `skills/`, `references/`, or `tools/`.
2. Put harness-specific configuration under `claude/`, `copilot/`, or `codex/`.
3. Add a manifest entry only when the corresponding directory exists.
4. Keep generated state and third-party installations outside this package.
5. Add a behavior check to `dev/ai-harness-check.py` when a stable contract can
   be tested without asserting documentation text.

Useful references:

- [Claude Code plugins](https://code.claude.com/docs/en/plugins-reference)
- [GitHub Copilot CLI plugins](https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-plugin-reference)
- [Codex configuration](https://developers.openai.com/codex/config-basic)
- [Codex skills](https://developers.openai.com/codex/skills)
- [Codex subagents](https://developers.openai.com/codex/subagents)
- [Codex hooks](https://developers.openai.com/codex/hooks)

## Validation

```sh
uv run -q --script dev/ai-harness-check.py
claude plugin validate --strict ai-harness
copilot --plugin-dir ai-harness plugin list
```

The repository check validates manifests, settings, and every skill with the
Agent Skills reference validator. The configuration was last checked against
Claude Code 2.1.221, Codex CLI 0.146.0, and Copilot CLI 1.0.80.

## Codex compatibility

Codex's `/etc` links can move to a user-level plugin layer when one can preserve
native state and live repository edits. Relevant upstream issues:
[openai/codex#11061](https://github.com/openai/codex/issues/11061),
[#14601](https://github.com/openai/codex/issues/14601),
[#24961](https://github.com/openai/codex/issues/24961), and
[#24770](https://github.com/openai/codex/issues/24770).
