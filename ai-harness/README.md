# Global AI Harness

One repo-owned layer of global instructions, skills, tools, and reviewed
settings for Claude Code, Codex, and GitHub Copilot CLI. Harness-owned runtime
state stays in each harness's real home directory.

> [!IMPORTANT]
> This branch is a reviewable scaffold. Nothing here is installed, linked, or
> loaded yet. The paths below describe the activation contract we will wire
> only after the structure and settings are approved.

## Design

There is no synchronization command and no dotfiles package for a harness
home. The repository owns authored files; symlinks and local plugin-directory
flags expose them in place. Editing an existing file or adding a skill takes
effect from the repository without copying it anywhere.

Third-party and harness-managed additions remain outside the repository. That
includes Workmux and BYOR hooks, installed plugins, downloaded skills,
permissions, trust decisions, sessions, caches, credentials, and UI state.

## Current layout

```text
ai-harness/
├── README.md                    # this ownership and extension contract
├── AGENTS.md                    # canonical global instructions
├── references/                 # progressive-disclosure context for AGENTS.md
├── skills/                     # home for reviewed, portable Agent Skills
├── tools/                      # reusable CLIs intended for agents
├── .claude-plugin/plugin.json  # Claude local-plugin identity
├── plugin.json                 # Copilot local-plugin identity
├── claude/settings.json        # reviewed launch-time settings
├── copilot/settings.json       # reviewed user-editable settings
└── codex/config.toml           # reviewed low-priority system settings
```

Directories for agents, hooks, status lines, or MCP configuration do not exist
until they contain something real. The recipes below define their future
locations so additions stay consistent.

## Ownership boundary

| Surface      | Repository owns                              | Harness or third party owns                                                     |
| ------------ | -------------------------------------------- | ------------------------------------------------------------------------------- |
| Instructions | `AGENTS.md` and `references/`                | Project instructions and temporary overrides                                    |
| Skills       | Direct children of `skills/`                 | `~/.agents/skills`, harness skill homes, installed plugins                      |
| Claude       | Plugin manifest and `claude/settings.json`   | Everything else under `~/.claude` and `~/.claude.json`                          |
| Copilot      | Plugin manifest and `copilot/settings.json`  | `config.json`, permissions, sessions, installed plugins, native additions       |
| Codex        | `codex/config.toml` and the admin skill root | User config, selected profile, hooks, trust hashes, projects, sessions, plugins |
| Workmux      | Existing top-level `workmux/` package        | Changes made by `workmux setup` inside harness homes                            |
| Theme        | Existing top-level `theme/` package          | Generated palette and runtime theme state                                       |

The ownership test is simple: if a harness or another application may update a
file automatically, that file stays real and untracked. The exceptions are
explicitly user-editable settings files: an interactive settings change there
is an intentional dotfiles change and should appear in Git.

## Planned activation

The future installer resolves the absolute path to this directory and creates
only these links. GNU Stow is not involved.

### Global instructions

```text
~/.codex/AGENTS.md                    -> ai-harness/AGENTS.md
~/.claude/CLAUDE.md                  -> ai-harness/AGENTS.md
~/.copilot/copilot-instructions.md   -> ai-harness/AGENTS.md

~/.codex/references                  -> ai-harness/references
~/.claude/references                 -> ai-harness/references
~/.copilot/references                -> ai-harness/references
```

The reference links make relative links in `AGENTS.md` work identically from
all three global instruction locations.

### Skills and tools

```text
/etc/codex/skills                    -> ai-harness/skills
~/.local/bin/lsp-check               -> ai-harness/tools/lsp-check.zsh
```

Codex scans `/etc/codex/skills` as its ADMIN scope independently from the USER
scope at `~/.agents/skills`. Normal user-level installers therefore cannot add
files to the repository. The link is organizational, not a security boundary:
a deliberately root-run process could still write through it.

Claude and Copilot receive `skills/` from the same repository directory through
their local plugin loaders. Neither plugin is installed or copied into a
marketplace cache.

### Settings and launchers

```text
/etc/codex/config.toml               -> ai-harness/codex/config.toml
~/.copilot/settings.json             -> ai-harness/copilot/settings.json
```

The shell launchers will preserve arbitrary arguments and add only these
defaults:

```sh
claude --plugin-dir "$AI_HARNESS" --settings "$AI_HARNESS/claude/settings.json"
copilot --plugin-dir "$AI_HARNESS"
codex --profile dotfiles
```

Claude's `--settings` file overlays its real user settings: omitted keys remain
user-controlled, while any reviewed tracked settings win for that session.

Copilot intentionally supports a symlinked `settings.json` and follows the
target when `/settings` writes. Runtime application state is now separated in
`config.json`, permissions files, databases, and other native paths.

Codex loads system settings below `~/.codex/config.toml` and the selected
profile. `~/.codex/dotfiles.config.toml` remains a real file; Codex may write
mutable UI or trust state there without touching Git. User and project layers
can override reviewed repo settings.

All three tracked settings files are intentionally empty in this scaffold.
Existing v1 preferences, MCP servers, plugins, features, and custom permission
presets will be reviewed individually before they are carried forward.

Workmux invokes Codex with the `dotfiles` profile, Luna at xhigh reasoning, and
`approval_policy = "on-request"` plus `approvals_reviewer = "auto_review"`.
That exact pair is the UI's **Approve for me** mode. Running `workmux setup`
remains allowed: its registered skills and hooks land in the real harness
homes, not here.

## Adding capabilities

### Skill

Create `skills/<name>/SKILL.md`. Every direct child is one independently
discoverable skill and may contain any supporting files or directories.
`SKILL.md` requires `name` and `description` frontmatter. Keep the skill itself
harness-agnostic; add `agents/openai.yaml` only when Codex-specific UI metadata,
invocation policy, or dependencies are useful.

The scaffold contains no migrated skills. Each v1 skill will be reviewed
separately before it is carried forward.

Do not put externally managed skills such as BYOR inside this directory, even
if ignored by Git. Their native user/plugin location is what preserves the
ownership boundary.

### Global reference

Add focused context under `references/` and link it from `AGENTS.md` or a skill.
References are not loaded merely because they exist; the link tells an agent
when deeper context is available.

### Agent

Create only the directories needed by the new agent:

```text
claude/agents/<name>.md
copilot/agents/<name>.agent.md
codex/agents/<name>.toml
```

Then add `"agents": "./claude/agents"` to the Claude manifest and
`"agents": "./copilot/agents"` to the Copilot manifest. Codex personal agents
are loaded from `~/.codex/agents`; when the first one exists, activation adds a
single `~/.codex/agents/dotfiles` directory link after a discovery smoke test
against the installed Codex version.

The formats are intentionally separate. Agent frontmatter and configuration
are not portable enough to justify a generated common schema.

### Hook

Put shared executable logic in `tools/` and keep registration harness-specific:

```text
claude/hooks/hooks.json
copilot/hooks.json
```

Add the corresponding `hooks` path to each plugin manifest. Put Codex hooks
inline in `codex/config.toml`, not in the mutable user `hooks.json`. Plugin and
system hooks compose with Workmux, BYOR, project, and user hooks; they do not
replace those sources. Hook scripts write mutable data under an XDG state or
cache directory, never inside the plugin.

Structural hook changes may require the harness's native reload command or a
new session. Ordinary script edits are live because the registered path points
into this repository.

### MCP or LSP server

Create a root `.mcp.json` only when the same definition works unchanged in
Claude and Copilot. Otherwise use `claude/.mcp.json` and `copilot/.mcp.json`
and reference them from the manifests. Codex definitions live under
`[mcp_servers]` in `codex/config.toml`. Credentials always come from the
environment or the harness's native credential store.

The same rule applies to LSP plugin configuration: share only a genuinely
portable file; otherwise keep one adapter per harness.

### Status line or theme adapter

The top-level `theme/` package owns color semantics and generated palettes.
Harness status-line scripts consume its generated state; they do not define a
second palette.

No harness theme is currently configured. In particular, Copilot's `theme`
setting selects only one of Copilot's built-in palettes; it cannot represent the
dotfiles semantic colors. Claude custom-theme and Codex `.tmTheme` adapters
should be added only when they actually consume the existing theme pipeline.

### Tool

Add an executable to `tools/` only when it is intended for agents across
projects. Link it individually into `~/.local/bin`; never link the whole tools
directory over a native application directory.

## Reload and diagnostics

| Harness | After editing existing content    | After adding structural content      | Inspect                                                                      |
| ------- | --------------------------------- | ------------------------------------ | ---------------------------------------------------------------------------- |
| Claude  | Usually immediate                 | `/reload-plugins` or restart         | `claude plugin validate --strict ai-harness`, `/status`, `/agents`, `/hooks` |
| Copilot | New session is safest             | Restart                              | `copilot --plugin-dir ai-harness plugin list`, `/skills list`                |
| Codex   | Skills are detected automatically | Restart when config or agents change | `codex doctor`, `/hooks`, `/agent`                                           |

Repository CI performs offline structure checks. Installed-CLI smoke tests are
manual because the three proprietary/current CLIs are not dependencies of this
dotfiles repository.

## Compatibility record

Reviewed **2026-08-18** against locally installed:

| Harness            | Version | Primary references                                                                                                                                                                                                                                                                                         |
| ------------------ | ------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Claude Code        | 2.1.221 | [Plugins](https://code.claude.com/docs/en/plugins-reference), [settings](https://code.claude.com/docs/en/settings)                                                                                                                                                                                         |
| Codex              | 0.146.0 | [Skills](https://developers.openai.com/codex/skills), [config](https://developers.openai.com/codex/config-basic), [hooks](https://developers.openai.com/codex/config-advanced), [agents](https://developers.openai.com/codex/subagents), [AGENTS.md](https://developers.openai.com/codex/guides/agents-md) |
| GitHub Copilot CLI | 1.0.80  | [Plugin reference](https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-plugin-reference), [configuration directory](https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-config-dir-reference)                                                                        |

Recheck the contract when a harness changes its discovery paths, manifest
schema, settings precedence, or reload behavior.

## Codex exit strategy

The `/etc/codex` links are a compatibility bridge until Codex offers a clean,
live user-level plugin/config layer that does not mix authored configuration
with mutable state. There is no public commitment or milestone today. Monitor:

- [#11061: easily share user preferences across machines](https://github.com/openai/codex/issues/11061)
- [#14601: prevent configuration pollution](https://github.com/openai/codex/issues/14601)
- [#24961: explicit config scopes and local state](https://github.com/openai/codex/issues/24961)
- [#24770: preserve symlinks for plugin installs](https://github.com/openai/codex/issues/24770)

When Codex gains direct local-plugin loading or a first-class authored
user-config layer, replace the `/etc` bridge with that native mechanism. Do not
maintain both paths.
