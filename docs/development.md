# Development

Every commit is gated by [prek](https://github.com/j178/prek): pinned
formatters, linters, and type checkers, defined once in
`.pre-commit-config.yaml` and run identically in CI.

The shellcheck and shfmt hooks pin Python 3.12 only for their isolated hook
installers; no project-wide Python version is selected. StyLua uses its
system-hook variant, with the pinned binary supplied by Homebrew on macOS and
the installer/CI npm step on Linux.

```sh
git config core.hooksPath .githooks   # enable the gate
prek run --all-files                  # run every check manually
```

Nothing in this repo is checked by review alone. If a rule matters, it is a
hook — and when a hook fails, the fix is the code, not a suppression.

## Where things live

Three directories, split by what a file _is_ rather than who happens to run
it:

| Directory  | Holds                                                                      |
| ---------- | -------------------------------------------------------------------------- |
| `ci/`      | check scripts invoked by a pre-commit hook — bespoke, one entry point each |
| `scripts/` | tools you run by hand, kept because they stay useful                       |
| `tests/`   | suites a test runner discovers and reports on (`pytest`, `node --test`)    |

Packages follow the same split locally: `tuis/rail/tests/` is the rail's
suite, `tuis/rail/scripts/` its render tools.

A throwaway debugging script belongs in none of them — delete it when the bug
is fixed. If it survives because it turned out to be genuinely useful, it has
earned a place in `scripts/`.

Tests must not read machine state. A suite that asserts against the live
theme, the real acknowledgment file, or the current mascot fails for reasons
that have nothing to do with the change under test. Point the environment at
a fixture and a temporary directory instead — the rail's `npm test` sets
`TUIS_COLORS_PATH` and `XDG_STATE_HOME` before node starts, because both are
read at import time.

## What the gate enforces

| Language   | Checks                                                       |
| ---------- | ------------------------------------------------------------ |
| Lua        | `stylua`, `lua-language-server --check`, annotation coverage |
| Python     | `ruff format`, `ruff check`, `ty`                            |
| Shell      | `shellcheck`, `shfmt`                                        |
| TypeScript | `oxlint`, `tsc --noEmit` (the rail)                          |
| Markdown   | `markdownlint`                                               |
| TOML/JSON  | `taplo`, `prettier`                                          |

Plus repo-specific checks: `keycheck` (the alt+/ cheatsheet can never drift from
the chords actually bound), and the rail's `ackcheck`, `attncheck`, and
escalation-hook checks.

## Lua typing

Lua is held to the same standard as TypeScript or Python here, which takes two
tools because neither is sufficient alone.

**`ci/luals-check.lua`** runs the same `lua-language-server` the editor runs,
with `no-unknown` at `Any!` — nothing may have an uninferable type. It resolves
the nvim runtime and every installed plugin as typed libraries, so CI sees what
the editor sees.

**`ci/annotation-check.lua`** covers what LuaLS structurally cannot. LuaLS
reports what it cannot _infer_; it is silent about a function that happens to be
inferable but is undocumented. This passes a strict LuaLS run cleanly:

```lua
local function join(a, b)
  return a .. b
end
```

So a second check parses every function with treesitter and requires a
`---@param` per parameter and a `---@return` on any function returning a value.
Parameters named `_` are skipped, `self` is implicit, and a zero-argument
function returning nothing needs no annotation — there would be nothing to say.

Types the project owns are declared in `nvim/lua/theme/init.lua`
and exposed to the editor through lazydev in `lua/plugins/lazydev.lua`, keyed on
the word `Theme`. That is what lets `highlights.lua` annotate against
`ThemeTokens` without requiring the module at runtime, while still loading
plugin libraries on demand.

## Commits

One self-contained change per commit, message in the form:

```text
<type>: <short summary>

<why, not what — no more than two lines>
```

Types: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`.

## Testing on tmux

Lifecycle experiments run on a throwaway socket (`tmux -L scratch`), never the
live server. Hooks fire globally, and a hook installed while experimenting will
follow you into real sessions.
