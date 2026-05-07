# Hunk Configuration

Hunk is the primary interactive Git diff/review viewer. It is installed from the
`hunkdiff` npm package, which provides the `hunk` CLI.

Install or validate just this tool through the dotfiles installer:

```bash
./scripts/install.sh --install-hunk
```

## Defaults

- `theme = "midnight"` - closest released built-in theme to the TokyoNight setup
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

## Theme Notes

Hunk custom theme support is not part of `hunkdiff` 0.10.0. When a release
includes `theme = "custom"`, this config should be updated to map the local
TokyoNight/Neovim palette into Hunk's `[custom_theme]` and
`[custom_theme.syntax]` sections.
