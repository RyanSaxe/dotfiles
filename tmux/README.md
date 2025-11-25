# Tmux Configuration

Comprehensive tmux configuration with TokyoNight Night theme, Pokemon-themed dynamic statusline, vim-tmux-navigator integration, and popup-based session management.

## Features

- **TokyoNight Night theme** - Consistent color scheme with Neovim/Ghostty
- **Pokemon theme integration** - Dynamic statusline colors that sync with Neovim dashboard Pokemon
- **Vim navigation** - Seamless pane switching between tmux and Neovim (via vim-tmux-navigator)
- **Popup windows** - FZF-powered session/Claude/notification management in floating popups
- **Prefix key** - `Ctrl+Space` (more ergonomic than default `Ctrl+B`)
- **Mouse support** - Click to select panes, resize splits, scroll history

## Key Bindings

### Prefix Key

- **Prefix** - `Ctrl+Space` (replaces default `Ctrl+B`)

### Pane Navigation & Management

```text
# Smart navigation (works with vim-tmux-navigator)
Ctrl+H/J/K/L    - Navigate left/down/up/right (works across tmux/vim)

# Fallback navigation (with prefix)
Prefix + h/j/k/l  - Navigate left/down/up/right

# Pane resizing (with prefix, repeatable)
Prefix + H/J/K/L  - Resize pane left/down/up/right by 5

# Window splits
Prefix + |        - Split horizontally (right)
Prefix + -        - Split vertically (down)
```

### Window Navigation

```text
# Quick window switching (no prefix needed)
Alt+1 to Alt+9   - Jump to window 1-9
Alt+N            - New window
Alt+Q            - Detach from session
```

### Popup Session Management

```text
# With prefix
Prefix + s       - Switch tmux sessions (ts)
Prefix + o       - Navigate to git repo (to)
Prefix + a       - Switch to Claude instance (tc)
Prefix + b       - Jump to panes with notifications (tb)

# Without prefix (Alt key)
Alt+S            - Switch tmux sessions
Alt+O            - Navigate to git repo
Alt+A            - Switch to Claude instance
Alt+B            - Jump to panes with notifications
```

### Copy Mode

```text
Prefix + [       - Enter copy mode
v                - Begin selection (in copy mode)
Ctrl+V           - Rectangle selection toggle
y                - Copy selection and exit
```

### Other

```text
Prefix + r       - Reload tmux configuration
```

## Configuration Structure

```text
tmux/
├── tmux.conf                          # Main configuration
└── scripts/
    ├── session-block.sh               # Session name with dynamic colors
    ├── window-status-block.sh         # Window tabs with dynamic colors
    ├── time-updater.sh                # Time display (right side)
    ├── color-cache-updater.sh         # Pokemon color sync (background)
    └── bell-cache-updater.sh          # Notification tracking (background)
```

## Dynamic Pokemon Theme

The statusline colors dynamically sync with the Pokemon displayed in your Neovim dashboard:

- **Session block** - Changes color based on state:
  - Default: dim Pokemon color
  - Prefix active: prominent Pokemon color
  - Notifications: bright Pokemon color

- **Window tabs** - Active window uses prominent/bright Pokemon colors, inactive uses dim

- **Background updaters** - Scripts run in the background to cache Pokemon colors from Neovim, preventing expensive script calls on every status bar render

## Minimal Mode

Tmux automatically detects popup windows (via `$TMUX_POPUP` environment variable) and uses minimal zsh configuration for faster popup loading.

## Zsh Integration

The configuration includes several zsh functions (defined in `zsh/functions/tmux.zsh`):

- **`tm [options] [commands...]`** - Create tmux session with predefined windows
  - `-n name|dir` - Session name or directory
  - `-c cmd` - Additional commands to run in windows
  - Shortcuts: `py` (ipython), `cc` (claude), `pr` (gh dash)

- **`ts`** - Switch between sessions with FZF
- **`tc`** - Jump to Claude instances (with attention indicators)
- **`tb`** - Jump to panes with bell notifications
- **`ta/td/tl/tk/tK`** - Basic tmux aliases (attach/detach/list/kill session/kill server)

## Customization

Edit `tmux.conf` to:

- Change prefix key
- Modify keybindings
- Adjust statusline format and position
- Change window/pane styling
- Disable Pokemon theme (use static TokyoNight colors)

Edit scripts in `scripts/` to customize statusline components.

## TODO

### Bugs

- [ ] Text highlighting doesn't display correctly with proper background color in tmux sessions

### Unclear How Hard

- [ ] Explore tmux navigation plugin improvements - evaluate if custom FZF popups can be replaced without performance degradation in popup windows
- [ ] Look into session history navigation plugins
