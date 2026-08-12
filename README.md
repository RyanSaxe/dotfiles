# dotfiles

Dotfiles for working from a Mac and SSHing into Linux boxes: Neovim, Ghostty,
herdr, zsh, and git, themed as one system and installed with GNU Stow. Coding
agents work inside the same environment and pass the same commit gates I do.

![screenshot](docs/screenshot.png)

## Install

```sh
git clone https://github.com/RyanSaxe/dotfiles && cd dotfiles
./install.sh
```

Clone it anywhere; nothing depends on where the repo lives. Works on a fresh
machine: installs homebrew itself on macOS, system packages,
and the symlinks for the tiers you pick — `core` everywhere, `mac` for GUI
apps, `agents` for the AI harness. Pass tiers as arguments to skip the
prompts (`./install.sh core` on a remote box), and re-run any time to update
packages and symlinks.

Each top-level directory is a stow package whose layout mirrors where its
files land:

```text
nvim/.config/nvim/init.lua  ->  ~/.config/nvim/init.lua
zsh/.zshrc                  ->  ~/.zshrc
```

Every tracked file is identical on every machine. Anything machine-specific
resolves at runtime via `PATH` and `$HOME`; there is no templating.

## Tools

| Package      | Contents                                                                                |
| ------------ | --------------------------------------------------------------------------------------- |
| `nvim`       | LazyVim-based Neovim. Personal plugins live in `nvim/dev/` as real, extractable plugins |
| `zsh`        | zsh with a starship prompt and automatic `.venv` activation                             |
| `ghostty`    | terminal emulator (macOS)                                                               |
| `herdr`      | agent-aware terminal multiplexer; runs on remote boxes, attached with `herdr --remote`  |
| `git`        | git + gh, delta as pager                                                                |
| `theme`      | the theming pipeline (below)                                                            |
| `ai-harness` | shared instructions, skills, and hooks for coding agents                                |
| `tiers`      | which packages install on which machines                                                |

## Theming

Catppuccin — Mocha in dark, Latte in light — rendered from one token file into
every tool. No config hardcodes a color; apps consume generated palettes and
reload in place:

```sh
theme dark
theme light
theme pokemon gengar   # accent colors extracted from a pokemon image
```

## Development

Every commit is gated by [prek](https://github.com/j178/prek): pinned
formatters, linters, and type checkers, defined once in
`.pre-commit-config.yaml` and run identically in CI.

```sh
git config core.hooksPath .githooks   # enable the gate
prek run --all-files                  # run every check manually
```
