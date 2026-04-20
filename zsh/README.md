# Zsh Configuration

Oh My Zsh-based shell configuration with custom theme, vi mode, automatic Python virtual environment activation, and comprehensive tmux/git repository management.

## Features

- **Oh My Zsh** - Framework for managing zsh configuration
- **Custom theme** - `fino-time-custom` (TokyoNight-inspired prompt)
- **Vi mode** - Vim keybindings in command line with visual mode indicator
- **Auto virtualenv** - Automatically activates Python virtual environments when entering project directories
- **Environment loading** - Auto-loads `.env` files with directory-specific caching
- **Tmux integration** - Session management and popup windows
- **Git repository navigation** - Fast fuzzy finding across projects
- **Minimal mode** - Lightweight configuration for tmux popups (automatic detection)

## Plugins

Plugins are managed declaratively via `config/zsh-plugins.txt` and installed to `~/.zsh-custom/plugins/` by `scripts/install.sh`.

### Included Plugins

| Plugin | Description |
| -------- | ------------- |
| **zsh-autosuggestions** | Fish-like ghost text suggestions from history |
| **zsh-completions** | Additional completion definitions |
| **zsh-history-substring-search** | Vim-style history search with up/down arrows |
| **fzf-tab** | Fuzzy completion menu powered by fzf |
| **fast-syntax-highlighting** | Real-time command syntax coloring |

### Keybindings

| Key | Action |
| ----- | -------- |
| `Tab` | FZF-tab completion menu (normal completions) |
| `Shift-Tab` | Accept ghost text from history (autosuggestions) |
| `↑` / `↓` | Search history for commands containing current input |

> **Convention**: `Tab` = normal completions, `Shift-Tab` = ghost text (consistent with Neovim)

### Managing Plugins

```bash
# Install plugins (runs automatically with install.sh)
./scripts/install.sh

# Update all plugins to latest
./scripts/install.sh --update-plugins

# Add a new plugin: edit config/zsh-plugins.txt, then re-run install.sh
```

## Configuration Structure

```text
zsh/
├── .zshrc                  # Main configuration (detects minimal mode)
├── .zshrc.minimal          # Lightweight config for tmux popups
├── aliases.zsh             # Shared command aliases
├── themes/
│   └── fino-time-custom.zsh-theme  # Custom Oh My Zsh theme
└── functions/
    ├── env.zsh             # Environment variable loading
    ├── vi-mode.zsh         # Vi mode enhancements
    ├── venv.zsh            # Python virtualenv auto-activation
    ├── tmux.zsh            # Tmux session management
    └── git-repos.zsh       # Git repository navigation
```

## Custom Functions

### Tmux Management (`tmux.zsh`)

- **`tm [options] [commands...]`** - Create/attach to tmux sessions

  ```bash
  tm                    # Create session named after current directory
  tm -n myproject       # Create session with custom name
  tm -c "git status"    # Create session with additional command window
  tm py cc              # Create session with ipython and claude windows
  ```

- **`ts`** - Switch between tmux sessions with FZF
- **`tc`** - Jump to Claude instances (shows notification indicators)
- **`tb`** - Jump to panes with bell notifications
- **`ta/td/tl/tk/tK`** - Tmux aliases (attach/detach/list/kill)

### Git Repository Navigation (`git-repos.zsh`)

- **`to`** - Navigate to git repos with FZF (searches `~/generic`, `~/work`, `~/projects`)
- **`cache_csv`** - Caching utility for expensive operations

### Environment Management

- **`env_init`** - Auto-loads `.env` files when entering directories
- **`venv_init`** - Auto-activates Python virtual environments
- **`vi_mode_init`** - Enables enhanced vi mode with indicators

## Minimal Mode

When `$TMUX_POPUP` is set or `ZSH_MODE=minimal`, zsh automatically loads `.zshrc.minimal` instead of the full configuration. This provides:

- Faster startup for tmux popup windows
- Essential functions only (no heavy plugins)
- Consistent environment for quick operations

## Theme Customization

The `fino-time-custom` theme provides:

- Git status indicators
- Python virtualenv display
- Current directory with smart truncation
- Time display
- TokyoNight-inspired colors

Customize by editing `themes/fino-time-custom.zsh-theme`.

## Vi Mode

Enhanced vi mode with:

- Visual mode indicator in prompt
- Vim-style line editing
- History search with vim bindings
- Integration with Oh My Zsh vi-mode plugin

## Aliases

Common aliases are defined in `aliases.zsh`. These are shared between full and minimal modes.

- `diagnose` runs `uvx ty check` in concise mode and prints a grouped `diagnostic: count` summary.

## Customization

Edit `.zshrc` to:

- Add/remove Oh My Zsh plugins
- Change theme
- Modify function behavior
- Add custom aliases
- Configure environment variables

Edit function files in `functions/` to customize specific behaviors.

## Environment Variables

Key variables set by this configuration:

- `$ZSH` - Oh My Zsh installation path (`~/.oh-my-zsh`)
- `$ZSH_CUSTOM` - Custom Oh My Zsh files (`~/.zsh-custom`)
- `$VIRTUAL_ENV_DISABLE_PROMPT` - Prevents duplicate virtualenv display
- `$TMUX_POPUP` - Detected automatically for minimal mode
