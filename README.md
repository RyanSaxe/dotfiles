# dotfiles

Dotfiles for working from a Mac and SSHing into Linux boxes: Neovim, Ghostty,
tmux, zsh, and git, themed as one system and installed with GNU Stow. Coding
agents work inside the same environment and pass the same commit gates I do.

```sh
git clone https://github.com/RyanSaxe/dotfiles && cd dotfiles
./install.sh
```

Clone it anywhere. On a fresh machine this installs homebrew, system packages,
and symlinks for the tiers you pick — `core` everywhere, `mac` for GUI apps.
See [docs/install.md](docs/install.md) for tiers, upgrades, and how the stow
layout stays out of the repo tree.

## What's in it

| Package      | Contents                                                                                              |
| ------------ | ----------------------------------------------------------------------------------------------------- |
| `ai-harness` | global instructions, shared skill and tool roots, plus Claude, Codex, and Copilot adapters            |
| `nvim`       | LazyVim-based Neovim, themed from the generated tokens                                                |
| `zsh`        | zsh with a starship prompt and automatic `.venv` activation                                           |
| `ghostty`    | terminal emulator (macOS)                                                                             |
| `sketchybar` | macOS menu bar replacement: workspaces, agent attention, battery/cpu/memory/wifi                      |
| `tmux`       | multiplexer, with [workmux](https://github.com/raine/workmux) for worktree-parallel agents and status |
| `workmux`    | global worktree-agent defaults, status integration, and ignored-file replication                      |
| `git`        | git + gh, delta as pager                                                                              |
| `bat`        | `cat` with syntax highlighting, themed from the same tokens                                           |
| `theme`      | the theming pipeline                                                                                  |
| `tiers`      | which packages install on which machines                                                              |

Each top-level directory is a stow package whose layout mirrors where its files
land, so `nvim/dot-config/nvim/init.lua` becomes `~/.config/nvim/init.lua`.
Every tracked file is identical on every machine; anything machine-specific
resolves at runtime.

## One keyboard, everywhere

The same bindings in the shell and the editor, so they feel like one tool:

- **Tab** — menu completion: open or cycle the menu (fzf-tab in zsh, blink.cmp
  in Neovim)
- **Shift-Tab** — accept ghost text (history suggestions in zsh, AI completions
  in Neovim)
- **vi-mode** in every input: beam cursor in insert, block in normal. No
  bindings on arrow keys, Ctrl, or Alt.

`alt+/` opens the keybind cheatsheet, which a commit hook keeps honest — a
chord that isn't listed fails the build.

## One theme, everywhere

Catppuccin rendered from a single token file into every tool. No config
hardcodes a color:

```sh
theme dark
theme inner light               # light terminal inside dark chrome
theme mascot pokemon:gengar     # accents extracted from a mascot image
```

Two surfaces switch independently — `inner` is content, `outer` is the chrome
around it — which is why a light editor can sit inside a dark frame. See
[docs/theming.md](docs/theming.md) for the pipeline, how to add a consumer, and
how to write a mascot provider.

## Working on it

Every commit is gated by [prek](https://github.com/j178/prek) — formatters,
linters, and type checkers pinned once and run identically in CI.

```sh
git config core.hooksPath .githooks   # enable the gate
prek run --all-files                  # run every check manually
```

See [docs/development.md](docs/development.md) for what each check enforces,
including how Lua is held to the same typing standard as the rest.

Also: [what was considered and left out](docs/considered.md).
