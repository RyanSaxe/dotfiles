# Hunk Configuration

Hunk is the primary interactive Git diff/review viewer. On macOS, it is
installed from the `modem-dev/tap/hunk` Homebrew formula. On Linux, the
dotfiles installer falls back to the `hunkdiff` npm package, which provides the
`hunk` CLI.

Install or validate just this tool through the dotfiles installer:

```bash
./scripts/install.sh --install-hunk
```

The macOS install path is equivalent to:

```bash
brew install modem-dev/tap/hunk
```

## Defaults

- `theme = "custom"` - TokyoNight Night palette tuned to match the local
  Neovim theme
- `mode = "auto"` - split on wide terminals, stack on narrow terminals
- `exclude_untracked = true` - avoids large-untracked-file crashes in current
  Hunk releases
- `agent_notes = true` - show agent-authored inline notes by default

## Workflow

Use normal Git commands for quick review:

```bash
git diff
git show HEAD
```

Use Hunk directly when you want the full review model:

```bash
hunk diff --watch
hunk show HEAD
```

When a Hunk session is open, agents can inspect and annotate it through
`hunk session ...` commands and the bundled Hunk review skill:

```bash
hunk skill path
```

## Feature Specs

- [Hunk follow and comment agent](./follow-comment-agent.md): implementation
  plan for a `hunk-follow` companion and Codex `hunk_commenter` subagent.

## Theme Notes

The custom theme maps Hunk's semantic theme slots to the local TokyoNight-based
Neovim palette:

- `#16161e` and `#1a1b26` for dark chrome and review backgrounds
- `#bb9af7`, `#fca7ea`, and `#f7768e` for purple, pink, and red accents
- `#73daca`, `#9ece6a`, and `#ff9e64` for teal, green, and orange code/diff
  emphasis
- `#565f89` and `#3b4261` for muted comments, gutters, and borders

Hunk cannot load Neovim highlight groups or dynamic dashboard colors directly,
so the config uses a static approximation of the local Neovim theme.
