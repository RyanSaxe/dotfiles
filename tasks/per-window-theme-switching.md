# Per-Tmux-Window Theme Switching

## Overview

Implement a dynamic theme switching system where each tmux window can independently be set to light or dark mode, coordinating changes across Ghostty (terminal), Tmux (status bar), and Neovim (colorscheme).

## Why This Approach?

**Use Case**: Different tmux windows serve different purposes - some for writing (Markdown, text), others for coding. Writing benefits from light mode (better readability), while coding often prefers dark mode.

**Key Insight**: Use tmux windows as the unit of theme state. Windows are persistent, well-scoped workflow boundaries that make perfect sense as the theme scope.

## Architecture

```
┌─────────────────────────────────────────┐
│ Tmux Session                            │
│                                         │
│  Window 1: "code"     (dark)  ← @window_theme="dark"
│  Window 2: "writing"  (light) ← @window_theme="light"
│  Window 3: "review"   (dark)  ← default: unset = dark
│                                         │
│  Hook: when window changes              │
│    → Read @window_theme                 │
│    → Apply theme to all tools           │
└─────────────────────────────────────────┘
```

## Implementation Plan

### 1. File Structure

```
dotfiles/
├── .gitignore                            # Add: */themes/current.conf
├── nvim/lua/
│   ├── plugins/
│   │   └── colorscheme.lua               # Loader: queries tmux, loads theme
│   └── themes/
│       ├── tokyonight-dark.lua           # Dark theme customizations
│       └── tokyonight-light.lua          # Light theme customizations
│
├── ghostty/
│   ├── config                            # Modified: config-file = themes/current.conf
│   └── themes/
│       ├── dark.conf                     # theme = TokyoNight Night
│       ├── light.conf                    # theme = TokyoNight Day
│       └── current.conf                  # Symlink (gitignored, runtime state)
│
└── tmux/
    ├── tmux.conf                         # Modified: keybind + hook + source theme
    ├── themes/
    │   ├── tokyonight-night.conf         # Dark theme variables
    │   ├── tokyonight-day.conf           # Light theme variables
    │   └── current.conf                  # Symlink (gitignored, runtime state)
    └── scripts/
        ├── toggle-theme.sh               # NEW: Toggle @window_theme
        ├── apply-theme.sh                # NEW: Apply theme to all tools
        └── (existing scripts)
```

### 2. Neovim Implementation

#### `nvim/lua/plugins/colorscheme.lua` (Loader)
```lua
-- Query tmux for the current window's theme setting
local function get_tmux_theme()
  -- Check if we're running inside tmux
  if not vim.env.TMUX then
    return "dark"
  end

  -- Query tmux for the current window's @window_theme option
  local handle = io.popen("tmux show-window-option -v @window_theme 2>/dev/null")
  if handle then
    local theme = handle:read("*a")
    handle:close()

    -- Trim whitespace and validate
    theme = theme:gsub("%s+", "")
    if theme == "light" then
      return "light"
    end
  end

  return "dark" -- Default
end

local theme = get_tmux_theme()
return require("themes.tokyonight-" .. theme)
```

#### Theme Files
- `nvim/lua/themes/tokyonight-dark.lua`: Copy existing `colorscheme.lua` content, ensure `style = "night"`
- `nvim/lua/themes/tokyonight-light.lua`: Duplicate and modify for light theme with `style = "day"`

**Key customizations for light theme**:
- Adjust comment colors: Use `Util.blend_bg(c.fg, 0.4)` instead of `c.dark3`
- Adjust inlay hints similarly
- Consider modifying dashboard key color to darker tone
- Test all highlight groups for readability on light background

### 3. Ghostty Implementation

#### `ghostty/config` modification
```conf
# Replace: theme = TokyoNight Night
# With:
config-file = themes/current.conf
```

#### Theme files
- `ghostty/themes/dark.conf`: `theme = TokyoNight Night`
- `ghostty/themes/light.conf`: `theme = TokyoNight Day`
- Both files can include additional customizations if needed

**Note**: Ghostty supports `config-file` directive to include other configs. The symlink pattern allows dynamic switching.

### 4. Tmux Implementation

#### `tmux.conf` modifications

1. **Add keybinding** (line ~175):
```bash
bind T run-shell '~/.config/tmux/scripts/toggle-theme.sh'
```

2. **Add hook** (line ~180):
```bash
set-hook -g after-select-window 'run-shell "~/.config/tmux/scripts/apply-theme.sh"'
```

3. **Source theme file** (replace lines 88-157):
```bash
# ==========================
# Theme Configuration
# ==========================
# Theme loaded from themes/current.conf (symlink)
source-file ~/.config/tmux/themes/current.conf
```

#### Theme files
- `tmux/themes/tokyonight-night.conf`: Extract lines 92-140 from current `tmux.conf`
- `tmux/themes/tokyonight-day.conf`: Create light variant with adjusted colors
  - Background: lighter shade
  - Foreground: darker text
  - Status bar: inverted contrast
  - Borders: visible on light background

### 5. Toggle Script

#### `tmux/scripts/toggle-theme.sh`
```bash
#!/usr/bin/env bash
# Toggle the current tmux window's theme between dark and light

# Get current theme (defaults to dark if not set)
current_theme=$(tmux show-window-option -v @window_theme 2>/dev/null || echo "dark")

# Toggle to opposite theme
if [ "$current_theme" = "light" ]; then
  new_theme="dark"
else
  new_theme="light"
fi

# Set the new theme for this window
tmux set-window-option @window_theme "$new_theme"

# Apply the theme immediately
~/.config/tmux/scripts/apply-theme.sh
```

**Make executable**: `chmod +x tmux/scripts/toggle-theme.sh`

### 6. Apply Script

#### `tmux/scripts/apply-theme.sh`
```bash
#!/usr/bin/env bash
# Apply the current window's theme to all tools (Ghostty, Tmux, Neovim)

# Get current window's theme (defaults to dark)
theme=$(tmux show-window-option -v @window_theme 2>/dev/null || echo "dark")

# Paths (adjust if needed for symlinked dotfiles)
GHOSTTY_DIR="$HOME/.config/ghostty/themes"
TMUX_DIR="$HOME/.config/tmux/themes"

# 1. Update Ghostty theme symlink
cd "$GHOSTTY_DIR" || exit 1
ln -sf "${theme}.conf" current.conf

# Reload Ghostty config (sends reload to all instances)
# Ghostty watches for config changes, but we can force with:
pkill -USR1 ghostty 2>/dev/null || true

# 2. Update Tmux theme symlink and reload
cd "$TMUX_DIR" || exit 1
ln -sf "tokyonight-${theme}.conf" current.conf

# Source the new theme in tmux
tmux source-file "$TMUX_DIR/current.conf" 2>/dev/null || true

# 3. Update all Neovim instances in current tmux window
# Find all nvim server sockets and send reload command
if [ "$theme" = "light" ]; then
  nvim_style="day"
else
  nvim_style="night"
fi

# Send remote command to all nvim instances
# Note: This is a simple approach; may need refinement for your setup
for server in /tmp/nvim.*.0; do
  if [ -S "$server" ]; then
    nvim --server "$server" --remote-send "<Esc>:lua require('tokyonight').load({style='$nvim_style'})<CR>" 2>/dev/null &
  fi
done

# Display notification
tmux display-message "Theme switched to: $theme"
```

**Make executable**: `chmod +x tmux/scripts/apply-theme.sh`

**Alternative Neovim approach**: Instead of sending remote commands, new nvim instances will automatically load the correct theme via the loader. For existing instances, you might prefer to manually reload or add an autocommand.

### 7. Git Configuration

Add to `.gitignore`:
```
# Runtime theme state (symlinks)
ghostty/themes/current.conf
tmux/themes/current.conf
```

**Why**: Since `~/.config/ghostty` and `~/.config/tmux` are symlinked to the dotfiles repo, runtime symlinks would otherwise be tracked by git.

### 8. Initial Setup

After implementing all changes:

```bash
# Create initial symlinks (defaults to dark)
cd ~/.config/ghostty/themes
ln -sf dark.conf current.conf

cd ~/.config/tmux/themes
ln -sf tokyonight-night.conf current.conf

# Reload tmux config
tmux source-file ~/.config/tmux/tmux.conf

# Restart or reload Ghostty
# (Cmd+R in Ghostty)
```

## Usage

1. **Toggle theme**: Press `<prefix>T` (e.g., `Ctrl+Space T`)
2. **Automatic switching**: When you switch to a different tmux window, the theme for that window is automatically applied
3. **New windows**: Default to dark theme
4. **New Neovim instances**: Automatically detect and use the current window's theme

## Important Considerations

### Symlink Pattern Safety

**Q**: Is it safe to dynamically switch what a file refers to via symlink?

**A**: Yes! This is a classic Unix pattern used extensively:
- **systemd**: `/etc/systemd/system/default.target` → symlink to target
- **alternatives**: `/usr/bin/python` → symlink to specific version
- **nginx/apache**: `sites-enabled/` → symlinks to `sites-available/`

**Why it works**:
- Symlink operations are atomic
- Applications re-read configs on reload (don't cache symlink resolution)
- No race conditions (you get either old or new config, both valid)

**Best practice**: Use relative symlinks when possible:
```bash
# Good (relative)
cd ~/.config/ghostty/themes && ln -sf dark.conf current.conf

# Less flexible (absolute)
ln -sf ~/.config/ghostty/themes/dark.conf ~/.config/ghostty/themes/current.conf
```

### Scope: All Panes in a Window

**Important**: All panes within a tmux window share the same theme. This is intentional - organize your workflow so that:
- **Writing window** = all panes in light mode
- **Code window** = all panes in dark mode
- **Mixed work** = use separate windows, not panes

This constraint encourages better workflow organization.

### Neovim Remote Commands

The `apply-theme.sh` script attempts to send commands to running Neovim instances. This has limitations:
- May not work if nvim wasn't started with server capability
- Socket locations may vary by setup
- New instances work perfectly (they query tmux on startup)

**Alternative**: Accept that existing nvim instances keep their theme until restarted, rely on new instances querying correctly.

### Ghostty Reload

Ghostty has multiple ways to reload config:
- `cmd+r` keybinding (manual)
- `pkill -USR1 ghostty` (signal-based)
- File watching (automatic in some versions)

Test which works best in your setup.

## Testing Plan

1. **Basic toggle**: Open tmux, press `<prefix>T`, verify all three tools switch theme
2. **Window persistence**: Toggle theme, switch to another window, switch back - should remember theme
3. **New windows**: Create new window, should default to dark
4. **New nvim**: In a light-themed window, open new nvim instance, should be light
5. **Pane behavior**: Split window into panes, toggle theme, all panes should update
6. **Session switching**: Switch to different tmux session, theme should be independent

## Future Enhancements

1. **Per-filetype in Neovim**: Automatically switch to light for .md/.txt files (use autocmd)
2. **Status indicator**: Show current theme in tmux status bar
3. **Session defaults**: Set default theme per session in tmux.conf
4. **Smooth transitions**: Add fade animations (if supported by terminal)
5. **Cursor shader variants**: Create light-mode version of `cursor_trail_tokyonight.glsl`

## References

- [TokyoNight.nvim](https://github.com/folke/tokyonight.nvim)
- [Ghostty Config Docs](https://ghostty.org/docs/config)
- [Tmux Manual](https://man.openbsd.org/tmux)
- Unix symlink pattern: Standard practice since AT&T Unix v7 (1979)
