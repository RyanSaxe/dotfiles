# Installing

```sh
git clone https://github.com/RyanSaxe/dotfiles && cd dotfiles
./install.sh
```

Clone it anywhere; nothing depends on where the repo lives. On a fresh machine
`install.sh` installs homebrew itself on macOS, then system packages and the
symlinks for the tiers you pick. Re-run it any time to update both.

After the first run, `dotfiles-install` is the front door from anywhere — a
zsh function resolving the repo through the `~/.zshrc` link, forwarding every
argument:

```sh
dotfiles-install                    # converge (interactive prompts)
dotfiles-install --non-interactive  # converge, assume yes, no input needed
dotfiles-install upgrade            # bump packages, before/after summary
dotfiles-install links              # relink only
```

Converge and upgrade are deliberately different verbs on the same command:
plain runs install what's missing and never bump working versions; `upgrade`
is the explicit "move everything forward" with its summary. `--non-interactive`
answers yes to every prompt and skips nothing; it needs cached sudo
(`sudo -v` first) and fails loudly without it. CI runs the real installer this
way on macOS and Linux, twice, on every change to the install path — the
first run proves it works, the second that it converges.

## Tiers

A tier is a set of system packages plus one symlink deployment map,
`tiers/<tier>.yaml`.

| Tier     | For                                               |
| -------- | ------------------------------------------------- |
| `core`   | everything, including remote Linux boxes over SSH |
| `mac`    | GUI applications — ghostty, sketchybar, aerospace |
| `extras` | optional tooling — byor and its ast-grep engine   |

Pass tiers as arguments to skip the prompts (`./install.sh core` on a remote
box). The default `./install.sh` runs `core agents` and asks separately about
the mac and extras tiers. `./install.sh links` redoes the symlinks alone, with
no package installs.

The `mac` tier has one prerequisite `install.sh` cannot satisfy for you.
sketchybar's wifi item reads `ipconfig getsummary en0`, which reports the SSID
only on a machine where this has been run once:

```sh
sudo ipconfig setverbose 1
```

Skip it and the wifi item still renders, showing the disconnected icon on a
connected machine.

Karabiner-Elements (Caps Lock as Escape, Ctrl+hjkl arrows outside terminals)
needs one approval on first run: open the app once and allow its driver
extension under System Settings > Privacy & Security. Until then the remaps
simply do not fire.

Nothing depends on `extras`, and declining it leaves no trace. Every entry in
its map carries its own `if` condition, so an extra whose tool is missing is
skipped while its neighbours still deploy — the tier is a list of independent
extras, not one switch. Adding one means adding entries and their condition to
`tiers/extras.yaml`; nothing outside that file needs to know.

For byor, the repo carries the part you write — `config.yml`, `rules/`,
`scripts/`. What byor writes stays local: `repos.yml` records absolute paths
for one machine, and `packages/` holds rules byor ships, which the tier
reinstalls through `byor package install` rather than the repo keeping copies
that drift.

The `core` and `agents` tiers each install the agent CLIs, link the AI harness,
and automatically run Workmux's non-interactive `setup --hooks --skills` pass.
This configures status hooks and bundled skills in the same install, including
explicit invocations such as `./install.sh core`; no follow-up `workmux setup`
command is required.

## Upgrading

```sh
./install.sh upgrade
```

Brings every package manager current — brew or apt, zsh plugins, the rail's
npm deps, uv tools, prek hook revs — and prints one before/after summary.

Version pins (the rail lockfile, prek revs) are bumped in the working tree but
never committed: review the diff and commit deliberately.

## How the symlinks work

[Dotbot](https://github.com/anishathalye/dotbot) deploys each tier's map,
`tiers/<tier>.yaml`, run through `uvx` by `install.sh`. A mapping names its
target explicitly. Config directories deploy as one directory symlink, so a
file added to the repo is live immediately:

```text
nvim/init.lua  ->  ~/.config/nvim/init.lua
zsh/zshrc      ->  ~/.zshrc
```

Directories that receive generated files at runtime stay real and use
individual links instead. For those per-file links, each map's `clean`
directive removes dead links that point into this repo, and only those — a dead
link belonging to another program is not ours to touch. Whole-directory links
do not create per-file links that can become orphaned.

Two guards run before deployment. Gitignored files inside the deployed source
trees are junk and get deleted, so a bytecode cache cannot become live
configuration through a directory link. Untracked files there refuse to deploy
— they may be unfinished work, and nothing unfinished should silently become
live configuration.

Every tracked file is identical on every machine. Anything machine-specific
resolves at runtime via `PATH` and `$HOME`; there is no templating.

### Generated files never land in the repo

Symlinks point from `$HOME` into the repo, never the reverse. Directories that
receive generated files at runtime — the rendered bat theme, ghostty shaders —
are pre-created as real directories by each map's `create` directive, so those
writes land in `$HOME` and not the checkout. The health workflow deploys into
a scratch home, runs `theme apply`, and fails if anything resolves into or
dirties the checkout.

**When adding a program that writes generated output under a deployed path**,
add its target directory to the `create` directive in the tier map. The health
check only exercises writes that happen during `theme apply`; anything written
at another time relies on that list.

Directory links include hidden files and nested files without separate map
entries.

## The vault

Notes live in a Markdown vault at `$VAULT_DIR` (`~/generic/vault`), which is a
git repository of its own and never part of the dotfiles. `install.sh` is the
only place that asks for one, and only when a human is driving it: it offers to
clone a vault repository you already have — `owner/repo` or a full URL — or to
create a fresh one, and then reports `vault check`. A scripted run does nothing
here, so installation never blocks on a prompt or creates a vault you did not
ask for.

The `vault` CLI owns the vault's shape and its task state:

```sh
vault tasks [--json]                           # a tree, or one row per task
vault task add <text> [--due DATE] [--branch]
vault task done <ID>                           # ID is <path>:<line>
vault task due <ID> <DATE>
vault init [path] [--in-place]
vault check
```

Task ids come from `vault tasks` and are recomputed every time, so nothing
stores one and none appears in the Markdown. Dates are read in every spelling
worth typing: `today`, `tmr`, a weekday (`fri`), `3d`, or `2026-08-25`. A
task's project is the basename of the current repository's git remote, which
means the same project resolves identically from every worktree of it.

Two files carry the vault's contract and `vault check` enforces both.
`.gitignore` is an allowlist: everything stays local except `public/`.
`.ignore` is the load-bearing one — obsidian.nvim builds a fixed
`rg --no-config` search command with no escape hatch, so without `.ignore`
every gitignored note vanishes from search, quick-switch, backlinks, and tags
with no error at all. It just looks like an empty vault. `check` catches that
by comparing what ripgrep can see against a filesystem walk, which is also why
a missing ripgrep fails the check rather than warning.

## Machine-local values

Anything that can't live in git — secrets, per-machine ids — goes in an
untracked `.env` at the repo root, which zsh and the rail launcher both load.
`install.sh` creates it with a commented placeholder per required value and
prints a loud reminder for every one still empty.

Today that list is `AGENT_NOTIFICATION_ID`, the ntfy.sh topic used for agent
phone notifications.

The `.env` also carries optional per-machine overrides, and `install.sh`
sources it so they apply from the first run. Keep values that depend on the
machine or local environment there; do not commit them to the repository.

`AGENT_NOTIFICATION_ID` is optional; leave it unset and agent phone
notifications simply never send. `rail status` reports the channel state.

The Pokémon mascot provider fetches data and images over HTTPS with Python's
standard library. `theme/bin/mascot-accents.py` declares Python 3.12 for that
script only; it does not set `UV_PYTHON`, so other `uv`, `uv run`, and `uvx`
commands can select the Python version required by their own project or tool.

On macOS, installing the `core` tier also installs a user-level launchd job.
It runs `~/.local/bin/attention refresh` at login and every five minutes. The
worker is independent of tmux and Neovim, writes durable state under
`~/.local/state/dotfiles/attention/`, and catches up after sleep or restart.
It uses a durable activity checkpoint with bounded paginated requests and a
periodic full reconciliation. It cannot poll while the Mac is fully powered
off. Refreshes back off until the GitHub rate-limit reset when the remaining
budget is under pressure.

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

To hear about repositories you are not otherwise involved in, list them in
`.env` rather than here:

```sh
ATTENTION_WATCH="someorg/infra someorg/docs"
```

Repository names are the one part of this configuration that can be
sensitive, and `.env` is the one file that never reaches git. It is already
sourced by the observer's launcher, so nothing else needs configuring.
Watching a repository covers its pull requests and its issues alike. Adding
one starts the watch at that moment. A watched repository might already have
hundreds of open pull requests or issues; those existing targets are not
backfilled. New targets and new comments on existing targets are reported
from the watch start onward. Removing and later re-adding a repository starts
a new watch.

Draft pull requests are excluded from watch-opened activity. Everything else
behaves as it does elsewhere: your own work never notifies you, and bots stay
suppressed unless allow-listed.

Inspect it with `attention status`, `attention list`, and
`attention ack <item-id>`. Each target has one row, even when it has several
reasons to need attention. The first successful sync establishes a clean
baseline, so old activity is not imported; later refreshes catch up while the
computer was asleep. Acknowledging a row clears its current activity revision,
and a later external comment or CI failure creates a new revision.
