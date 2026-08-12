# dotfiles

My development environment, rebuilt for a workflow where AI coding agents are
first-class users of the machine: shared quality gates, one theming system
across every tool, and nothing configured that isn't earned by daily use.

Managed with [GNU Stow](https://www.gnu.org/software/stow/). Each top-level
directory is a stow package whose layout mirrors the filesystem, so the repo is
its own documentation:

```text
nvim/.config/nvim/init.lua  ->  ~/.config/nvim/init.lua
zsh/.zshrc                  ->  ~/.zshrc
```

## Principles

- **Symlinks, never copies.** Configs are edited live. Every tracked file is
  byte-identical on every machine; anything machine-specific resolves at
  runtime through `PATH` and `$HOME`, never through templating.
- **Tokens, not colors.** One palette and one semantic token layer generate
  per-app themes. Light and dark are two bindings of the same tokens, and no
  config hardcodes a hex value.
- **One gate for humans, agents, and CI.** Every commit passes the same pinned
  formatters, linters, and type checkers, locally and in CI, from a single
  config. Agents working in this repo hit the same wall a human does.
- **State never lands in git.** Files that tools write back to are generated
  and ignored, not tracked.

## Development

Every commit is gated by [prek](https://github.com/j178/prek) through the
hooks in `.githooks/`:

```sh
git config core.hooksPath .githooks   # enable the gate
prek run --all-files                  # run every check manually
```

Checks are pinned in `.pre-commit-config.yaml`. CI runs the identical config,
so a passing local commit cannot fail remotely.
