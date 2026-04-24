# Codex Configuration

Codex has both shareable instruction layers and mutable local state. This repo should only manage the shareable pieces.

Recommended split:

- `codex/AGENTS.md` -> `~/.codex/AGENTS.md`
- `codex/rules/shared.rules` -> `~/.codex/rules/shared.rules`

Keep these local and out of dotfiles:

- `~/.codex/config.toml` - user defaults plus machine-specific and trusted-project state
- `~/.codex/rules/default.rules` - approvals Codex writes for you from the TUI
- auth, history, logs, caches, and sessions under `~/.codex/`

Tracked files:

- `AGENTS.md` - Reusable cross-machine Codex instructions
- `rules/shared.rules` - Reusable approval rules worth sharing across machines

If you want repo-specific Codex settings, use a project-level `.codex/config.toml` inside that repo instead of trying to sync your entire `~/.codex/config.toml`.
