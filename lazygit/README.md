# LazyGit Configuration

LazyGit TUI configuration with TokyoNight Night theme and delta integration for syntax-highlighted diffs.

## Features

- **TokyoNight theme** - Custom colors matching Neovim/Tmux color scheme
- **Delta integration** - Syntax-highlighted diffs via delta with TokyoNight theme
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

### Delta Integration

```yaml
git:
  paging:
    colorArg: always
    pager: delta --paging=never --syntax-theme=tokyonight_night
```

Provides syntax-highlighted diffs within LazyGit, consistent with command-line git.

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
- Adjust git behavior (paging, commit graph, etc.)
- Add custom keybindings

See [LazyGit docs](https://github.com/jesseduffield/lazygit/blob/master/docs/Config.md) for all available options.
