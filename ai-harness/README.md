# AI Harness

Shared configuration and utilities for AI coding agents.

## Layout

- `AGENTS.md`: global cross-agent instructions. This is model context only.
- `skills/`: canonical local Agent Skills directory using the `SKILL.md` format.
- `notify.sh`: deterministic notification hook target for Claude, Codex, and Copilot.
- `codex/hooks.json`: Codex lifecycle hook configuration.
- `copilot/settings.json`: Copilot CLI user settings for hooks and built-in beep behavior.
- `tmux/agent-utils.sh`: generic tmux helpers for finding AI agent panes.
- `tmux/attention-daemon.sh`: tmux metadata watcher for Codex panes whose title enters `Action Required`.

Codex also gets a launch-time `notify=[...]` override from the repo-owned zsh
`codex()` wrapper, so Codex can pass notification JSON to `notify.sh` without
editing `~/.codex/config.toml`.

## Notification Environment

Set one of these environment variables to enable ntfy notifications:

- `AI_HARNESS_NTFY_TOPIC`: ntfy.sh topic name.
- `AI_HARNESS_NTFY_URL`: full ntfy endpoint URL.

The script always attempts a terminal BEL unless `AI_HARNESS_DISABLE_BELL=1`.
Set `AI_HARNESS_NOTIFY_DEBOUNCE_SECONDS` to tune duplicate suppression; the default is `2`.
