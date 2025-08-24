# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a personal dotfiles repository that provides automated development environment setup across macOS and Ubuntu/Debian systems. The repository uses a configuration-driven approach where package lists and symlink mappings are defined in text files, making it easy to manage without code changes.

## Architecture

### Core Components

- **Configuration Files** (`config/`):
  - `brew-packages.txt` / `apt-packages.txt`: Package dependencies (one per line)
  - `symlinks.txt`: Dotfile mappings in format `source:target` (one per line)

- **Installation Scripts** (`scripts/`):
  - `install.sh`: Full environment setup (installs packages, tools, and creates symlinks)
  - `symlink.sh`: Dotfiles symlinking management with backup/restore functionality

- **Tool Configurations**:
  - `nvim/`: LazyVim-based Neovim setup with custom plugins and configurations
  - `zsh/`: Oh My Zsh configuration with custom theme (`fino-time-custom`)
  - `bat/`, `ghostty/`, `git/`: Individual tool configurations

### Symlink System

The repository uses a sophisticated symlink management system:
- Configuration-driven via `config/symlinks.txt`
- Automatic backup of existing files to `backups/` with timestamps
- Restore instructions generated in `backups/RESTORE_INSTRUCTIONS.txt`
- Safe handling of existing symlinks vs real files

## Common Development Commands

### Environment Setup
```bash
# Full new machine setup
./scripts/install.sh

# Preview symlink changes without making them
./scripts/symlink.sh --dry-run

# List all configured symlinks
./scripts/symlink.sh --list

# Create/update symlinks only
./scripts/symlink.sh
```

### Package Management
```bash
# Add new packages to respective files:
echo "new-package" >> config/brew-packages.txt     # macOS
echo "new-package" >> config/apt-packages.txt      # Ubuntu/Debian

# Then run full install to add them
./scripts/install.sh
```

### Neovim Development
The Neovim configuration is LazyVim-based with custom plugins in `nvim/lua/plugins/`. Key features:
- LazyVim plugin manager with auto-updates enabled
- Custom configurations in `nvim/lua/config/`
- Additional tooling integrations (SonarLint, Copilot, etc.)
- TokyoNight theme consistency across all tools

## Key Dependencies

### Core Tools (Auto-installed)
- **neovim**: Primary editor (LazyVim setup)
- **ripgrep/fzf/fd**: Fast search tools used extensively by Neovim plugins
- **lazygit**: Terminal UI for git operations
- **uv**: Modern Python package manager (installed via web script)
- **gh**: GitHub CLI for repository operations

### Development Languages
- **openjdk@17**: Required for SonarLint LSP in Neovim
- **node/npm**: For JavaScript tooling and Neovim LSP servers
- **python3**: With uv for modern Python development

### Special Installations
Some tools require manual installation scripts in `install.sh`:
- **tectonic**: LaTeX engine (installed from GitHub releases)
- **lazygit**: Git TUI (installed from GitHub releases)
- **Pokemon Colorscripts**: Terminal eye candy

## Platform Support

- **macOS**: Full support via Homebrew
- **Ubuntu/Debian**: Full support via apt with additional PPAs for latest versions
- Cross-platform configurations designed to work consistently

## Neovim Configuration Details

### Structure
- `init.lua`: Bootstraps LazyVim
- `lua/config/`: Core LazyVim configuration (keymaps, options, autocmds)
- `lua/plugins/`: Custom plugin configurations
- `lua/custom/`: Project-specific utilities (git operations, scratch buffers)
- `lua/functions/`: Reusable Neovim functions

### Key Features
- Integrated terminal management with floaterm
- Git workflow enhancements (diffview, custom pickers)
- Advanced completion with blink-cmp
- Code formatting and linting setup
- SonarLint integration for Java projects

## Software Versions & Compatibility

**IMPORTANT**: Always write code compatible with these specific versions to avoid compatibility issues:

### Shell Environment
- **Bash**: 3.2.57 (macOS default - limited features, no associative arrays)
  - Scripts must be compatible with Bash 3.2 (avoid Bash 4+ features)
  - Use `#!/usr/bin/env bash` for portability
- **Zsh**: 5.9 (primary shell, feature-rich)

### Core Development Tools
- **Neovim**: 0.11.2 (modern Lua configuration support)
  - Uses Lua 5.4.7 for configurations
  - LazyVim requires Neovim >= 0.9.0
- **Python**: 3.13.4 (latest stable)
- **Node.js**: v24.2.0 (for LSP servers and tooling)
- **Java**: OpenJDK 17.0.15 (required for SonarLint)

### System Environment
- **OS**: macOS Darwin 23.6.0 (Ventura/Sonoma)
- **Architecture**: arm64 (Apple Silicon)

### Critical Compatibility Notes
- **Bash Scripts**: Must work on macOS's ancient Bash 3.2 - avoid modern features
- **Neovim Config**: Requires Lua 5.4+ syntax and Neovim 0.11+ APIs
- **Package Managers**: Homebrew (macOS) vs apt (Linux) - see respective package lists
- **Java Projects**: Require `JAVA_HOME` pointing to OpenJDK 17 for SonarLint functionality

## Important Notes

- The `tasks/` directory contains development TODOs and ideas
- Backup system ensures no data loss during dotfile updates
- All configurations use TokyoNight theme for visual consistency
- Shell includes automatic Python virtual environment activation
- Java environment requires `JAVA_HOME` pointing to openjdk@17