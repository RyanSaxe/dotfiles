# dotfiles

Dotfiles for working from a Mac and SSHing into Linux boxes: Neovim, Ghostty,
tmux, zsh, and git, themed as one system and installed with GNU Stow. Coding
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

`./install.sh upgrade` brings every package manager current — brew or apt,
zsh plugins, the rail's npm deps, uv tools, prek hook revs — and prints one
before/after summary. Version pins (the rail lockfile, prek revs) are bumped
in the working tree but never committed: review the diff and commit
deliberately.

Each top-level directory is a stow package whose layout mirrors where its
files land:

```text
nvim/.config/nvim/init.lua  ->  ~/.config/nvim/init.lua
zsh/.zshrc                  ->  ~/.zshrc
```

Every tracked file is identical on every machine. Anything machine-specific
resolves at runtime via `PATH` and `$HOME`; there is no templating.

## Tools

| Package      | Contents                                                                                              |
| ------------ | ----------------------------------------------------------------------------------------------------- |
| `nvim`       | LazyVim-based Neovim. Personal plugins live in `nvim/dev/` as real, extractable plugins               |
| `zsh`        | zsh with a starship prompt and automatic `.venv` activation                                           |
| `ghostty`    | terminal emulator (macOS)                                                                             |
| `sketchybar` | macOS menu bar replacement, aerospace/battery/cpu/memory/wifi widgets                                 |
| `tmux`       | multiplexer, with [workmux](https://github.com/raine/workmux) for worktree-parallel agents and status |
| `git`        | git + gh, delta as pager                                                                              |
| `bat`        | `cat` with syntax highlighting, themed with Catppuccin                                                |
| `theme`      | the theming pipeline (below)                                                                          |
| `ai-harness` | shared instructions, skills, and hooks for coding agents                                              |
| `tiers`      | which packages install on which machines                                                              |

## Conventions

The same keybinding model everywhere, so the shell and the editor feel like
one tool:

- **Tab** — menu completion: open or cycle the menu (fzf-tab in zsh, blink.cmp
  in Neovim)
- **Shift-Tab** — accept ghost text (history suggestions in zsh, AI
  completions in Neovim)
- **vi-mode** in every input: beam cursor in insert, block in normal. No
  bindings on arrow keys, Ctrl, or Alt.

## Theming

Catppuccin — Mocha in dark, Latte in light — rendered from one token file into
every tool. No config hardcodes a color; apps consume generated palettes and
reload in place:

```sh
theme dark
theme light
theme inner light
theme outer dark
theme both toggle
theme mascot pokemon:gengar   # accent colors extracted from a mascot image
```

The theme has two independently switchable surfaces. `inner` is terminal and
content chrome (including Ghostty's native palette, shells, prompts, and bat);
`outer` is the surrounding chrome (SketchyBar, the rail, tmux separators, and
the Ghostty frame shader). Inner mode drives macOS appearance so Ghostty keeps
its native light/dark theme pair; outer mode never changes the OS appearance.
This permits combinations such as a light terminal inside dark chrome.

Every consumer is registered as inner or outer in
`theme/.config/theme/elements.conf`; mixed consumers use explicit namespaced
tokens such as `{{inner_bg}}` and `{{outer_crust}}`.

### Mascot providers

A mascot is any image the theme system can wear: the rail paints its sprite
and the accent/notify colors are extracted from it. Identities are
provider-qualified (`pokemon:gengar`), and providers live in
`theme/.local/bin/mascot-accents` as a registry — the picker, completions,
and rail all build from it, so adding a source touches exactly one file.

A provider is two functions registered under a name:

```python
def _my_identities() -> list[str]:
    # What the picker offers. An API list, a directory of dropped
    # images (identity = filename), anything enumerable.
    ...

def _my_fetch(identity: str) -> MascotImages:
    # Cache under mascot_cache("my-source") and return the sprite PNG
    # the rail paints plus the image accents extract from — often the
    # same file (pokemon extracts from richer official artwork).
    ...

register("my-source", Provider(_my_identities, _my_fetch))
```

That's the whole surface. `theme mascot my-source:<id>`, the fzf picker
entry, per-project sync, and the rail sprite all follow from the
registration — see the `pokemon` provider for a full example and
`shiny-pokemon` for wrapping an existing source as its own picker entry.

## Development

Every commit is gated by [prek](https://github.com/j178/prek): pinned
formatters, linters, and type checkers, defined once in
`.pre-commit-config.yaml` and run identically in CI.

```sh
git config core.hooksPath .githooks   # enable the gate
prek run --all-files                  # run every check manually
```
