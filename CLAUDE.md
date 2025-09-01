# Claude Code Dotfile Instructions

This is a personal dotfiles repository that provides automated development environment setup across macOS and Ubuntu/Debian systems. The repository uses a configuration-driven approach where package lists and symlink mappings are defined in text files, making it easy to manage without code changes.

## Style Guide

- Always try and match TokyoNight theme colors across all tools. For customizations, refer to the `nvim/lua/plugins/colorscheme.lua` file.
- While the global CLAUDE.md specifies not to leave lots of comments, since I am less familiar with shell/lua, please leave more detailed comments in this repo.
- Always refer to the global CLAUDE.md for how I expect you to work. Do not forget to commit often and write good commit messages.

## Folder Structure

- **Configuration Files** (`config/`):
  - `brew-packages.txt` / `apt-packages.txt`: Package dependencies (one per line)
  - `symlinks.txt`: Dotfile mappings in format `source:target` (one per line)

- **Installation Scripts** (`scripts/`):
  - `install.sh`: Full environment setup (installs packages, tools, and creates symlinks)
  - `symlink.sh`: Dotfiles symlinking management with backup/restore functionality

- **Tool Configurations**:
  - `[TOOL]/`: Will have the specifications for configuring TOOL. You can find where the TOOL will be symlinked in `config/symlinks.txt`.

## Version Information

You can always check versions via the command line, but here are the key versions to ensure compatibility:

- **Bash**: 3.2.57 (macOS default - limited features, no associative arrays)
- **Zsh**: 5.9 (primary shell, feature-rich)
- **Neovim**: 0.11.2 (modern Lua configuration support)
- **Lua**: 5.4.7 (used by Neovim)
- **Tmux**: 3.5a (stable version)

**IMPORTANT**: Always write code compatible with these specific versions to avoid compatibility issues. And remember, this is platform agnostic, so make sure that the code you write is compatible with both macOS and Linux (Ubuntu/Debian).

## Neovim Distribution

The Neovim configuration is LazyVim-based with custom plugins in `nvim/lua/plugins/`. Make sure to read through the LazyVim documentation for understanding the base setup.

## Important Notes

- The `tasks/` directory contains development TODOs and ideas

