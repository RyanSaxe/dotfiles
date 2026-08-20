# Installing

```sh
git clone https://github.com/RyanSaxe/dotfiles && cd dotfiles
./install.sh
```

Clone it anywhere; nothing depends on where the repo lives. On a fresh machine
`install.sh` installs homebrew itself on macOS, then system packages and the
symlinks for the tiers you pick. Re-run it any time to update both.

## Tiers

A tier is a set of stow packages, declared in the `tiers` package.

| Tier   | For                                               |
| ------ | ------------------------------------------------- |
| `core` | everything, including remote Linux boxes over SSH |
| `mac`  | GUI applications — ghostty, sketchybar, aerospace |

Pass tiers as arguments to skip the prompts (`./install.sh core` on a remote
box). The default `./install.sh` runs `core agents` and asks separately about
the mac tier. `./install.sh stow` redoes the symlinks alone, with no package
installs.

When the core or agents tier installs the agent CLIs, the installer links the
AI harness first and then automatically runs Workmux's non-interactive
`setup --hooks --skills` pass. This configures status hooks and bundled skills
in the same install, including explicit invocations such as
`./install.sh core agents`; no follow-up `workmux setup` command is required.

## Upgrading

```sh
./install.sh upgrade
```

Brings every package manager current — brew or apt, zsh plugins, the rail's
npm deps, uv tools, prek hook revs — and prints one before/after summary.

Version pins (the rail lockfile, prek revs) are bumped in the working tree but
never committed: review the diff and commit deliberately.

## How the symlinks work

Each top-level directory is a stow package whose layout mirrors where its files
land. Hidden targets are named with a `dot-` prefix (stow's `--dotfiles` mode)
so repo content stays visible to `rg`, `fd`, and editors:

```text
nvim/dot-config/nvim/init.lua  ->  ~/.config/nvim/init.lua
zsh/dot-zshrc                  ->  ~/.zshrc
```

The existing `~/.config/nvim` target is an explicit cutover boundary. If it is
already a symlink from the v1 configuration, the installer leaves it in place
and continues installing the other packages; v2 Neovim is adopted only during
the deliberate cutover phase.

Every tracked file is identical on every machine. Anything machine-specific
resolves at runtime via `PATH` and `$HOME`; there is no templating.

### Why folding is disabled

Symlinks point from `$HOME` into the repo, never the reverse, and generated
files never land in the repo tree. Stow can violate this on its own: when a
target directory does not exist it "folds" — links the whole directory into the
repo — and every later write into that directory lands inside the package.
Three layers prevent it:

- `.stowrc` passes `--no-folding`: real directories, per-file links. It only
  applies when stow runs from the repo root and the file parses.
- `install.sh` pre-creates every directory that receives generated files at
  runtime (`RUNTIME_WRITE_DIRS`) as a real directory before stowing, which
  holds even when `.stowrc` is not read.
- The health workflow stows into a scratch home, runs `theme apply`, and fails
  if anything resolves into or dirties the checkout.

**When adding a program that writes generated output under a stowed path** — as
`theme` publishes the rendered bat theme and ghostty shaders — add its target
directory to `RUNTIME_WRITE_DIRS` in `install.sh`. The health check only
exercises writes that happen during `theme apply`; anything written at another
time relies on that list.

## Machine-local values

Anything that can't live in git — secrets, per-machine ids — goes in an
untracked `.env` at the repo root, which zsh and the rail launcher both load.
`install.sh` creates it with a commented placeholder per required value and
prints a loud reminder for every one still empty.

Today that list is `AGENT_NOTIFICATION_ID`, the ntfy.sh topic the rail and
GitHub attention observer use for phone notifications. Leave it unset and
phone notifications simply never send; `rail status` and `attention status`
report the channel state.

On macOS, installing the `core` tier also installs a user-level launchd job.
It runs `~/.local/bin/attention refresh` at login and every five minutes. The
worker is independent of tmux and Neovim, writes durable state under
`~/.local/state/dotfiles/attention/`, and catches up after sleep or restart.
It cannot poll while the Mac is fully powered off. Refreshes back off until
the GitHub rate-limit reset when the remaining budget is under pressure.

The observer uses the existing `gh` authentication. Before relying on it, run
`gh auth status` and re-authenticate with `gh auth refresh -h github.com` if
needed. Optional actor policy lives at
`~/.config/dotfiles/attention.json`:

```json
{
  "actors": {
    "allow": ["claude-reviewer"],
    "ignore": ["codecov", "snyk-bot", "sonarcloud"]
  },
  "own_pr_ci": true
}
```

Inspect it with `attention status`, `attention list`, and
`attention ack <item-id>`. The notification transport remains ntfy for now;
the planned transport evaluation is recorded in `BACKLOG.md`.
