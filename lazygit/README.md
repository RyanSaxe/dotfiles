# LazyGit Configuration

LazyGit TUI configuration with TokyoNight Night theme, delta-backed embedded
diffs, and Hunk terminal review commands.

## Features

- **TokyoNight theme** - Custom colors matching Neovim/Tmux color scheme
- **Delta integration** - Syntax-highlighted embedded diffs via delta with
  TokyoNight theme
- **Hunk commands** - Full-screen Hunk review sessions launched from LazyGit
- **Nerd Fonts** - File icons using Nerd Fonts v3
- **Borders & UI** - Enhanced visual layout with borders and bottom status line

## Configuration Highlights

### Theme Colors

Carefully matched to TokyoNight Night palette:

- **Active border** - Bright blue (`#7aa2f7`)
- **Inactive border** - Muted gray (`#545c7e`)
- **Search border** - Orange highlight (`#ff9e64`)
- **Selected line** - Subtle blue tint (`#283457`)
- **Unstaged changes** - Teal (`#73daca`)
- **Cherry-picked commits** - Purple (`#bb9af7`)

### Diff Integration

```yaml
git:
  pagers:
    - colorArg: always
      pager: delta --paging=never --syntax-theme=tokyonight_night
```

Delta stays as the embedded LazyGit pane renderer because it is non-interactive
and works with LazyGit's pager contract. Hunk owns an alternate-screen terminal
UI, so it is launched through custom commands instead.

### Hunk Commands

- `<c-h>` in the status panel opens `hunk diff --watch`
- `<c-h>` on a file opens that file's unstaged or staged diff in Hunk
- `<c-h>` on a commit opens `hunk show <commit>`

## Usage

Launch LazyGit from any git repository:

```bash
lazygit
```

Or use the Neovim integration (if configured) via keybindings.

## Customization

Edit `config.yml` to:

- Modify theme colors (all colors defined in `gui.theme` section)
- Change UI preferences (`showCommandLog`, `splitDiff`, etc.)
- Adjust git behavior (delta pager, commit graph, etc.)
- Add custom keybindings

See [LazyGit docs](https://github.com/jesseduffield/lazygit/blob/master/docs/Config.md)
for all available options.
