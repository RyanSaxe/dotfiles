# 🚀 Dotfiles - Development Environment Anywhere

This repository contains my complete development environment setup including dotfiles for various tools and automation scripts to set up any new machine quickly. All configurations are version controlled and automatically symlinked for easy management.

The main assumption is that personal machines are MacOS, but that this continues to work on linux such that it can be easily set up (at least a light version) for sshing into a linux machine

## 📁 Structure

```
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
# TODO: the below does not exist yet and needs to handle cloning my private notes if used by me
./script/setup-notes.sh # create all scaffolding for obsidian notes to work with neovim according to how I use them
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

Ideas I have, but have not implemented yet. Or that I've tried and was too much work for that time.

Note: will move most of these TODOs to downstream README.md files once the todo list picker and README.md for subfolders on this list is done.

### Bugs

- [ ] When in a tmux session, highlighting text does not look correct and properly put a nice highlight behind the selected text
- [ ] In rare, unreproducible scenarios, sometimes the `u` neovim command for `undo` doesn't work and neovim needs to be restarted

### Simple

- [ ] Look into proper usage of things like surround and what automatically fills parentheticals, but where "tab" can effectively break you out of it instead of having to go back to normal mode.
- [ ] Change completion prioritization such that TAB always cycles through blink completions if available. In that case, Shift Tab should take the copilot completion instead of cycling backwards through blink completions.
- [ ] generalize the obsidian todo list picker to actually take a working directory, so it can search across markdown files in any directory. This also of course means letting the setting the due date mechanism work here too.
- [ ] Explore not having exact same background color (c.bg in colorscheme.lua) for all statuslines (including tmux) and even my Ghostty background. Debating moving to equivalent of exactly how snacks sets up the opacity for picker backgrounds blended so that when opening a picker that has a partially transparent dark background, it perfectly melds into these borders. Another option is to actually go FULL #000000 black so that it blends into the edges of a Mac itself, though this only will look good in full screen. I would want the active bufferline tab and such to have c.bg as a very clean visual indicator for it too.
- [ ] Add README.md to relevant subfolders to make it easier to explore and communicate the normal way of using the tool and working.
- [ ] Break out my dependency picker into a real neovim plugin instead.
- [ ] Create the `scripts/setup-notes.sh` script.
- [ ] Setup this github repo to have the full CI/CD suite with things like: release automation, proper linting/formatting, and relevant precommit hooks
- [ ] Cleanup the look of which-key.nvim to not be so cluttered with all the LazyVim defaults. Importantly organize the groups I have and give them proper names and icons.
- [ ] Implement a "stacked pr" command for claude-code such that it can take work on a branch, and break it up into multiple PRs such that the PRs are nicely separated by concept and stacked if relevant.
- [ ] Revisit markdown linting and proper setup of markdown and text files with blink, rendering, and formatting. Especially to play nice with frontmatter and flexibility with claude and obsidian.
- [ ] Actually have leader key have fully exhaustive lists of keybinds to make navigation extremely easy.
- [ ] Reorganize structure of plugins to be folder based (e.g. lsp/ and snacks/ instead of flat .lua files)

### Unclear How Hard

- [ ] Explore improvements to tmux navigation, possibly via using plugins. Could remove my customized tmux fzf stuff, though I can't replace this if those plugins aren't smart about minimal loading to avoid lag in tmux popups. Also of course look at like session history navigation.
- [ ] Move my current hammerspoon init to be one such spoon, and then make other spoons with really nice automation that can cleanly be integrated with leader key
- [ ] Need to fully relook at automated linting with LSPs and Conform specifically.
- [ ] Actually properly configure sonarlint, and especially create a really nice customization of it for lsp-check that can work beyond python of course.
- [ ] Figure out the best way to cleanly reactivate snippets and create nice snippet customization. I hated them at the beginning and how they populated and distracted with my completions menu. I want to revisit this and figure out what works for me.

### Complex

- [ ] Fully sync light/dark mode such that my tmux statusline and ghostty config automatically updates too ... likely will not prioritize as I don't use light mode enough, but actively would want if I ever break my colorscheme out into a real one. This would mean coming out of the box with more robust cross-language customization and themes for other applications (e.g. bat, git delta).
- [ ] Fully dive deep into best feasible setup for python LSP. I have done a good amount of work here, but ty will come out at some point and I will likely want to redo everything. And I'll want it to be way more complex, where it should be able to work with projects that have specifications in their pyproject.toml that suggests a different LSP (e.g. pyright).
- [ ] Setup claude code to work very nicely with tmux and a REPL like ipython. Most likely through a very involved and complicated skill in which CLAUDE.md is very aggressive to tell it to use the skill frequently.
- [ ] Dig super deep into the different git workflows. From snacks.nvim's gh module, to diffview, and mini.diff. As well as even gh-dash and lazygit. I have all of these as dependencies, but at the moment there's a bit of a bleed. Need to fully optimize git workflows eventually since I use them all the time.

## Applications/Plugins to Try

Things I have not explored yet but am interested in taking a look at

- [ ] Aerospace: Tiling window manager
- [ ] SkechyBar: MacOS Statusline
- [ ] Zoxide:    Smart directory navigation (e.g. replace for cd)
- [ ] I don't remember the name, but it's a neovim plugin for merging the statusline with tmux for a much cleaner look. Though I would want to not have tmux in the middle as it's default and would want tmux to the left and neovim to the right, which might be complicated.
- [ ] Vimium:    Chrome Extension for vim navigation of chrome. Right now I do have it enabled, but have not customized it. The extension has a restore option from a JSON file, so we can have a config here. I'd like to disable A LOT in it so it doesn't conflict with native keybinds. And instead use things like either karibiner or leader key to natively map things like pageup/pagedown as well as arrow keys and stuff so it's not specific to chrome. But this way I can keep link navigation and make vimium look nicer (the default css is gross)
