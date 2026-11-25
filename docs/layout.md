# Layout

`flake.nix` builds each computer from a host file in `hosts/` that lists its
roles. Macs get a nix-darwin system config (`modules/darwin`) plus a Home
Manager config (`modules/home`); Linux boxes get Home Manager only. Each module
enables itself for the roles it belongs to.

`flake.nix` exports `lib.mac` and `lib.home` so private machines can live in a
separate flake with their own host file and secrets; see
[Setup](setup.md#a-computer-built-from-a-private-flake).

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../assets/layout-dark.svg">
  <img alt="Dotfiles host, role, and module layout. hosts/mac.nix (aarch64-darwin) enables the gui, base, and personal roles. hosts/linux.nix (x86_64-linux) enables the base, personal, and rex-server roles. Each role enables its modules: gui enables ghostty, aerospace, sketchybar, karabiner, macos, darwin/macos, and darwin/homebrew; base enables zsh, git, tmux, neovim, packages, ws, agents, secrets, and darwin/codex; personal enables rex plus personal extras in agents, packages, and theme; rex-server enables the rex-server systemd user service." src="../assets/layout-light.svg">
</picture>

| Role         | Adds                                                       |
| ------------ | ---------------------------------------------------------- |
| `base`       | Shell, editor, CLI tools and agent settings                |
| `gui`        | Mac window manager, status bar, fonts, apps and settings   |
| `personal`   | Claude Code, Antigravity CLI, Rex config and byor rules    |
| `rex-server` | Rex server as a systemd user service                       |

Some modules check a second role (`packages` adds fonts for `gui`, plus `pi` and
Python for `personal`). The `theme` module applies everywhere.

Rex is the primary terminal. tmux (with Ghostty on macOS) is configured with the
same key bindings and popups for machines without Rex.

## Files

```text
flake.nix           inputs and host outputs
hosts/              per-machine roles and settings
modules/
  options.nix       host option definitions
  home/             one Home Manager module per program
  darwin/           nix-darwin macOS settings, Homebrew casks and /etc/codex
  codex-managed.nix files Codex's managed hooks read in /etc/codex
theme/              color meanings, per-app templates and the `theme` script
pkgs/               ws (Go), pair package and tmux patch
config/             raw program configs symlinked from this checkout
ai-harness/         agent instructions, references, skills and hooks
secrets/            secrets.yaml encrypted to the age keys in .sops.yaml
tests/              prompt tests, checks tests and placeholder work host for CI
docs/               these pages
assets/             README screenshots, layout diagram SVGs and retake.sh
```

Most files under `config/` and `ai-harness/` symlink directly into this
checkout, so edits apply on next start or reload. Everything else (plus a few
linked files read at build time) requires a switch; see
[AGENTS.md](../AGENTS.md#applying-a-change).
