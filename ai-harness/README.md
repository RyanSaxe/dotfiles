# AI Harness

Shared configuration and utilities for AI coding agents.

## Layout

- `AGENTS.md`: global cross-agent instructions. This is model context only.
- `skills/`: canonical local Agent Skills directory using the `SKILL.md` format.
- `scripts/notify.sh`: deterministic notification hook target for Claude, Codex, and Copilot.
- `scripts/agent-utils.sh`: generic tmux helpers for finding AI agent panes.
- `scripts/attention-daemon.sh`: tmux metadata watcher for Codex panes whose title enters `Action Required`.
- `claude/`: Claude-specific configs (CLAUDE.md, settings.json, hooks, references, themes, utility-scripts).
- `codex/hooks.json`: Codex lifecycle hook configuration.
- `codex/dotfiles.config.toml`: Shared Codex profile selected by the zsh
  wrapper with `--profile dotfiles`.
- `copilot/settings.json`: Copilot CLI user settings for hooks, status line, and built-in beep behavior.
- `copilot/utility-scripts/`: Copilot CLI command status line scripts.

Codex also gets a launch-time `notify=[...]` override from the repo-owned zsh
`codex()` wrapper, so Codex can pass notification JSON to `scripts/notify.sh`
without editing `~/.codex/config.toml`.
The same wrapper passes native Codex status line settings and machine-expanded
environment paths at launch. `~/.codex/config.toml` remains local mutable state
for trusted project paths, hook trust hashes, UI flags, and connector-specific
settings.

## Notification Environment

Set one of these environment variables to enable ntfy notifications:

- `AI_HARNESS_NTFY_TOPIC`: ntfy.sh topic name.
- `AI_HARNESS_NTFY_URL`: full ntfy endpoint URL.

The script always attempts a terminal BEL unless `AI_HARNESS_DISABLE_BELL=1`.
Set `AI_HARNESS_NOTIFY_DEBOUNCE_SECONDS` to tune duplicate suppression; the default is `2`.
