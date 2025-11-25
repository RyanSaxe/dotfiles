# 🚀 Dotfiles - Development Environment Anywhere

This repository contains my complete development environment setup including dotfiles for various tools and automation scripts to set up any new machine quickly. All configurations are version controlled and automatically symlinked for easy management.

The main assumption is that personal machines are MacOS, but that this continues to work on linux such that it can be easily set up (at least a light version) for sshing into a linux machine

## 📁 Structure

```text
config/                    # Configuration files for dependencies and symlinks
├── brew-packages.txt      # Homebrew packages (one per line)
├── apt-packages.txt       # APT packages (one per line)
└── symlinks.txt           # Dotfile mappings (source:target per line)
...
some-application/          # Folder for some application I use regularly enough to customize
├── README.md              # Relevant documentation for how this application is set up
└── ...                    # any files and folders relevant to the application
...
scripts/                   # Scripts related to these dotfiles directly
├── install.sh             # Full environment setup
├── symlink.sh             # Dotfiles symlinking management
└── lsp-check.sh           # A command line tool for extracting LSP diagnostics
```

## 🚀 Quick Start

This configuration assumes the existance of three folders in the home directory:

1. `~/generic`: where generalized content (e.g. notes, dotfiles) sit
2. `~/work`: where files related to work sit
3. `~/projects`: where personal projects sit

While it's of course fine for code and content to sit elsewhere, you may need to modify the code to accomodate that. For example, there is automation for navigating to git repos that scans the above folders. You will need to add other folders to that script if you want them scanned.

### New Machine Setup

In order to set up your machine, execute the following:

```bash
mkdir -p ~/generic ~/work ~/projects
# TODO: make official releases of stable variants so this can point to most stable release
git clone https://github.com/RyanSaxe/dotfiles ~/generic/dotfiles
cd ~/generic/dotfiles
./scripts/install.sh # install all necessary dependencies and apps
./scripts/symlink.sh # symlink configs to the right place so apps recognize them
./scripts/setup-notes.sh # create all scaffolding for obsidian notes to work with neovim
# Optional: clone your private notes repository (requires SSH access)
./scripts/setup-notes.sh --clone-private
```

Note that, especially for symlinks, you may want to see what will happen first by running these commands:

```bash
# Preview what would be symlinked
./scripts/symlink.sh --dry-run

# List all configured dotfile mappings  
./scripts/symlink.sh --list

# Create symlinks (done automatically by install.sh)
./scripts/symlink.sh
```

However, don't worry, if that script deletes anything, it will create a directory in `~/generic/dotfiles/backup` and put them there so you can properly revert if needed.

## 🔧 Manual Configuration Steps

Some tools require additional manual setup after installation. This is because they either cannot be managed by configuration files perfectly, or they are not easily integrated with common mechanisms to download dependencies or work across different machines trivially.

Please find details on all those tools below. I do my best to minimize this as much as possible.

### SonarLint

SonarLint is the LSP server for SonarQube so that we can get real SonarQube feedback as diagnostics in Neovim. Note this repo has not been setup yet to automatically work with Enterprise SonarQube and repository specific things yet.

1. Open Neovim and run `:MasonInstall sonarlint-language-server`
2. Set `JAVA_HOME` environment variable to point to openjdk@17 (installed by install.sh script)

### Leader Key

Leader Key must have some of it's configuration (e.g. was the actual leader key is, how quickly the popup opens) set through the MacOS application settings directly. I have personally set it up such that right_shift triggers it, but you can set it however you would like. You just do need to manually enable this one.

Additionally, I recommend setting Leader Key to

1. Always show cheatsheet
2. show leader key on the monitor with the mouse. Other options have issues when using full screen.

### Accessibility Settings

Ghostty, Karabiner, Leader Key, and Hammerspoon need to be enabled with special permissions and accessibility settings. Additionally, I personally recommend Leader Key and Hammerspoon to open when you login for the smoothest experience.

## 🎨 Theme

Generally speaking, all applications are set up to share as close to the same dark theme as possible, which is a branch off of Tokyonight Night theme.

This does mean that switching any application to another theme will likely look very bad. Eventually I may make time for this not to be the case.

## TODO

Repository-wide tasks and cross-cutting improvements. Tool-specific TODOs are in their respective README files (e.g., `nvim/README.md`, `tmux/README.md`).

### Simple

- [x] Create the `scripts/setup-notes.sh` script for Obsidian notes scaffolding
- [ ] Setup CI/CD: release automation, linting/formatting, precommit hooks
- [ ] Implement "stacked PR" command for claude-code to break work into multiple linked PRs

### Complex

- [ ] Sync light/dark mode across tmux statusline, ghostty, and other tools automatically
- [ ] Setup Claude Code to work seamlessly with tmux and REPL (ipython) - likely requires custom skill

## Applications/Plugins to Try

Things I have not explored yet but am interested in taking a look at

- [ ] Aerospace: Tiling window manager
- [ ] SkechyBar: MacOS Statusline
- [ ] Zoxide:    Smart directory navigation (e.g. replace for cd)
- [ ] I don't remember the name, but it's a neovim plugin for merging the statusline with tmux for a much cleaner look. Though I would want to not have tmux in the middle as it's default and would want tmux to the left and neovim to the right, which might be complicated.
- [ ] Vimium:    Chrome Extension for vim navigation of chrome. Right now I do have it enabled, but have not customized it. The extension has a restore option from a JSON file, so we can have a config here. I'd like to disable A LOT in it so it doesn't conflict with native keybinds. And instead use things like either karibiner or leader key to natively map things like pageup/pagedown as well as arrow keys and stuff so it's not specific to chrome. But this way I can keep link navigation and make vimium look nicer (the default css is gross)
