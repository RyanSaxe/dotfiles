# Installing

```sh
git clone https://github.com/RyanSaxe/dotfiles && cd dotfiles
./install.sh
```

Clone it anywhere; nothing depends on where the repo lives. On a fresh machine
`install.sh` installs homebrew itself on macOS, then system packages and the
symlinks for the tiers you pick. Re-run it any time to update both.

## Tiers

A tier is a set of system packages plus one symlink deployment map,
`tiers/<tier>.yaml`.

| Tier   | For                                               |
| ------ | ------------------------------------------------- |
| `core` | everything, including remote Linux boxes over SSH |
| `mac`  | GUI applications — ghostty, sketchybar, aerospace |

Pass tiers as arguments to skip the prompts (`./install.sh core` on a remote
box). The default `./install.sh` runs `core agents` and asks separately about
the mac tier. `./install.sh links` redoes the symlinks alone, with no package
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

[Dotbot](https://github.com/anishathalye/dotbot) deploys each tier's map,
`tiers/<tier>.yaml`, run through `uvx` by `install.sh`. A mapping names its
target explicitly; directories deploy through a glob, which creates real
directories containing per-file links and picks up new files automatically:

```text
nvim/dot-config/nvim/init.lua  ->  ~/.config/nvim/init.lua
zsh/dot-zshrc                  ->  ~/.zshrc
```

Renaming or deleting a repo file cannot leave a link dangling: each map's
`clean` directive removes dead links that point into this repo, and only
those — a dead link belonging to another program is not ours to touch. One
consequence of per-file links is that emptied directories are left behind as
empty real directories rather than removed.

Two guards run before deployment. Gitignored files inside the deployed source
trees are junk and get deleted, so a glob can never link a bytecode cache into
`$HOME`. Untracked files there refuse to deploy — they may be unfinished work,
and nothing unfinished should silently become live configuration.

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

One more glob caveat: Python's glob skips hidden files, so a dotted filename
inside a globbed directory needs its own explicit mapping (as
`~/.config/nvim/.luarc.json` has) or it silently never deploys.

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

To hear about repositories you are not otherwise involved in, list them in
`.env` rather than here:

```sh
ATTENTION_WATCH="someorg/infra someorg/docs"
```

Repository names are the one part of this configuration that can be
sensitive, and `.env` is the one file that never reaches git. It is already
sourced by the observer's launcher, so nothing else needs configuring.
Watching a repository covers its pull requests and its issues alike.

Adding one is quiet. A watched repository might already have hundreds of open
pull requests; the first poll that sees it records the moment, and only work
opened after that is ever reported. The timestamp is kept even if you remove
the entry later, so re-adding a repository stays quiet too.

Drafts are excluded, and a draft marked ready later counts as opened at that
moment. Everything else behaves as it does elsewhere: your own work never
notifies you, and bots stay suppressed unless allow-listed.

Inspect it with `attention status`, `attention list`, and
`attention ack <item-id>`. `attention status` reports notification-transport
failures separately from GitHub failures: a phone notification that cannot be
delivered never stops the observer from polling.
