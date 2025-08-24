# 🚀 Dotfiles - Development Environment Anywhere

This repository contains my complete development environment setup including dotfiles for various tools and automation scripts to set up any new machine quickly. All configurations are version controlled and automatically symlinked for easy management.

## 📁 Structure

```
nvim/                       # Neovim configuration (LazyVim)
bat/                        # bat (cat with syntax highlighting)  
ghostty/                    # Ghostty terminal emulator
zsh/                        # Zsh shell configuration and themes
git/                        # Git configuration (global ignore, etc.)
scripts/                    # Installation and management scripts
├── install.sh             # Full environment setup
└── symlink.sh             # Dotfiles symlinking management
```

## 🚀 Quick Start

### New Machine Setup
```bash
git clone https://github.com/RyanSaxe/lazy.nvim ~/.config/nvim
cd ~/.config/nvim
./scripts/install.sh
```

This single command will:
1. Install all development dependencies (neovim, ripgrep, fzf, etc.)
2. Set up shell environment (zsh, oh-my-zsh)
3. Install additional tools (lazygit, uv, etc.)
4. Automatically symlink all dotfiles to their proper locations

### Manual Dotfiles Management
```bash
# Preview what would be symlinked
./scripts/symlink.sh --dry-run

# List all configured dotfile mappings  
./scripts/symlink.sh --list

# Create symlinks (done automatically by install.sh)
./scripts/symlink.sh
```

## 🔧 Manual Configuration Steps

Some tools require additional manual setup after installation:

### SonarLint (Java)
1. Open Neovim and run `:MasonInstall sonarlint-language-server`
2. Set `JAVA_HOME` environment variable to point to openjdk@17 (installed by script)

## 🎨 Included Configurations

- **Neovim**: Full LazyVim setup with custom plugins and keybindings
- **bat**: Syntax highlighted file viewing with TokyoNight theme
- **Ghostty**: Terminal with vim-style split management and TokyoNight theme

## 📝 Managing Your Dotfiles

### Making Changes
1. Edit files in the tool directories (e.g., `nvim/`, `zsh/`)
2. Changes are immediately reflected (thanks to symlinks)
3. Commit changes: `git add . && git commit -m "your changes"`

### Version Control Benefits
- **Rollback**: `git checkout HEAD~1` to undo recent changes
- **History**: `git log --oneline` to see all configuration changes
- **Branching**: Test major changes on branches before merging

### Adding New Dotfiles
1. Add config files to appropriate `toolname/` directory
2. Update `DOTFILE_MAPPINGS` in `scripts/symlink.sh`  
3. Run `./scripts/symlink.sh` to create new symlinks

## 🌍 Cross-Platform Support

The installation script supports:
- **macOS**: via Homebrew
- **Ubuntu/Debian**: via apt with additional PPAs for latest versions

All configurations are designed to work consistently across platforms.
