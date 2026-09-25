# Working in this repository

These instructions are for the dotfiles repository itself. The global ones
every project gets are [ai-harness/AGENTS.md](ai-harness/AGENTS.md).

## Checks

`prek` runs the same checks as the commit gate and CI, so it is the
authority on whether a change passes. Iterate with a targeted run and finish
with the full one:

```sh
prek run --files path/to/changed.lua another/file.ts
prek run --all-files
```

That covers formatting, linting, types, shell, the harness contract with its
test suites, and the Lua typecheck. The Lua half is `ci/luals-check.lua`,
which drives the same lua-language-server the editor runs, with every
installed plugin supplied as a typed library, so it sees what your editor
would show in a file you never opened. Run it alone when only Lua changed:

```sh
nvim -l ci/luals-check.lua
```

None of this proves a feature works. In-editor behavior, rendering, and
keybindings need the real interface, so open Neovim and use the thing you
changed.

## Test fixtures that run git

Git hands `GIT_DIR`, `GIT_WORK_TREE` and `GIT_INDEX_FILE` to hooks and to
the commands `git rebase -x` runs, and they override the working directory.
A fixture that creates a repository strips every `GIT_*` variable from the
environment it gives git and checks that the repository git ended up in is
the one it just created, before it writes anything;
`tests/visual-review/build.test.mjs` and
`tuis/rail/tests/workspace.test.ts` show the shape. Without that, a suite
run from the commit hook reinitialises this repository as bare and commits
into it.
