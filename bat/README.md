# Bat Configuration

Bat is a `cat` clone with syntax highlighting and Git integration, configured here with the TokyoNight Night theme for consistent styling.

## Configuration

The `config` file contains:
```
--theme="tokyonight_night"
```

This ensures all syntax highlighting uses the TokyoNight Night color scheme, matching Neovim, Tmux, Ghostty, and other tools in this repository.

## Usage

Use `bat` anywhere you would normally use `cat`:

```bash
# View a file with syntax highlighting
bat file.py

# View multiple files
bat src/*.rs

# Pipe output (disables paging automatically)
curl -s https://example.com | bat -l html

# Show only specific line ranges
bat -r 10:20 file.js
```

## Customization

Edit `config` to change the theme or add other options. For available themes:
```bash
bat --list-themes
```
