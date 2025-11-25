# IPython Configuration

IPython REPL configuration with TokyoNight Night color scheme for syntax highlighting, matching the Neovim theme.

## Features

- **TokyoNight theme** - Custom color overrides for prompts, syntax tokens, and error messages
- **Dark terminal colors** - Configured for dark backgrounds (`linux` mode)
- **Auto-clear on startup** - Clears the screen when starting IPython (via `startup/00-clear-screen.py`)

## Configuration Structure

```text
ipython/
├── profile_default/
│   ├── ipython_config.py          # Main config with TokyoNight colors
│   └── startup/
│       └── 00-clear-screen.py     # Auto-clear screen on startup
```

## Color Scheme

The configuration overrides Pygments token colors to match TokyoNight Night:

- **Keywords/Operators** - Purple (`#9d7cd8`)
- **Functions** - Orange (`#ff9e64`)
- **Classes** - Teal (`#1abc9c`)
- **Variables** - Blue (`#89ddff`)
- **Strings/Numbers** - Foreground (`#c0caf5`)
- **Errors** - Red (`#f7768e`)
- **Prompts** - Blue/Magenta highlights

## Usage

Simply start IPython from any terminal:

```bash
ipython
```

The TokyoNight theme will be automatically applied with proper syntax highlighting.

## Customization

Edit `profile_default/ipython_config.py` to modify:

- Color overrides in `highlighting_style_overrides` dictionary
- Terminal colors via `c.TerminalInteractiveShell.colors`
- Other IPython settings (autocomplete, history, etc.)

Add new startup scripts in `profile_default/startup/` (they run in alphabetical order).
