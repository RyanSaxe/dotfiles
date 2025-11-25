# Ghostty Configuration

Ghostty terminal emulator configuration with TokyoNight Night theme, vim-style split management, and custom cursor trail shader.

## Features

- **TokyoNight Night theme** - Consistent with Neovim/Tmux color scheme
- **Vim-style splits** - Navigate and create splits using vim-inspired keybindings
- **Global quick terminal** - Toggle terminal overlay with `Cmd+G` from anywhere
- **Copy-on-select** - Automatic clipboard copy when selecting text
- **Custom cursor shader** - TokyoNight-themed cursor trail effect
- **Claude Code integration** - Multi-line support with `Shift+Enter`

## Key Bindings

### Split Management

```text
# Create splits (vim-style hjkl)
Cmd+Shift+L  - New split right
Cmd+Shift+H  - New split left
Cmd+Shift+J  - New split down
Cmd+Shift+K  - New split up

# Navigate splits
Cmd+L  - Go to split right
Cmd+H  - Go to split left
Cmd+J  - Go to split down
Cmd+K  - Go to split up

# Resize splits
Cmd+Shift+Arrow  - Resize split in arrow direction by 10 pixels
```

### Other

```text
Cmd+G (global)  - Toggle quick terminal
Cmd+R           - Reload configuration
Cmd+O           - Open configuration file
Shift+Enter     - Multi-line input (for Claude Code)
```

## Configuration Highlights

### Styling

- **Font size** - 16pt
- **Unfocused opacity** - 0.8 (dims inactive splits)
- **Window padding** - 4px on all sides (improves lualine appearance)
- **Padding color** - Matches background

### Custom Shader

```ini
custom-shader = shaders/cursor_trail_tokyonight.glsl
```

Provides a subtle cursor trail effect with TokyoNight colors.

## Customization

Edit `config` to:

- Modify keybindings (use `keybind = key=action` format)
- Change font size or family
- Adjust opacity and padding
- Disable or change the cursor shader
- Add global keybindings with `global:` prefix

See [Ghostty docs](https://ghostty.org/docs) for all available options.
