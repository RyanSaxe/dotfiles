# btop Configuration

Terminal-based resource monitor with TokyoNight Night theme.

## Features

- **Custom TokyoNight Night theme** matching nvim/lazygit colors
- **Vim-style navigation** (h/j/k/l/g/G) - hold Shift for help (H) and kill (K)
- **Braille graph symbols** for highest resolution
- **All panels enabled**: CPU, Memory, Network, Processes

## Key Bindings

| Key | Action |
|-----|--------|
| `h/j/k/l` | Navigate (vim-style) |
| `g/G` | Go to top/bottom |
| `H` | Help menu (Shift+h) |
| `K` | Kill process (Shift+k) |
| `f` | Filter processes |
| `t` | Toggle tree view |
| `e` | Toggle per-core CPU |
| `+/-` | Expand/collapse tree |
| `q` | Quit |

## Theme Colors

Custom theme using exact TokyoNight Night palette:

- Background: `#1a1b26`
- Foreground: `#c0caf5`
- Borders: `#545c7e`
- Highlights: `#7dcfff` (cyan)
- Graph gradients: green→yellow→red for CPU/temp, teal→blue for memory/network

## Customization

- Config: `~/.config/btop/btoprc`
- Custom themes: `~/.config/btop/themes/`
- Press `Esc` in btop to access options menu
