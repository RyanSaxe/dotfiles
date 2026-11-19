# Layout

`flake.nix` lists each computer. A Mac gets a nix-darwin config, built from
`modules/darwin`, and every computer gets a Home Manager config, built from
`modules/home`. Both read the computer's host file in `hosts/`, which names
its roles, and each module turns itself on for the roles it belongs to.

`flake.nix` builds these configs with `lib.mac` and `lib.home`, which it
also exports. A computer whose details stay out of this repository is
built from a private flake that calls them with a host file of its own, as
[Setup](setup.md#a-computer-built-from-a-private-flake) shows.

```mermaid
flowchart LR
  subgraph Hosts
    mac["hosts/mac.nix"]
    linux["hosts/linux.nix"]
  end
  subgraph Roles
    gui
    base
    personal
    rexServer["rex-server"]
  end
  subgraph Modules
    guiModules["ghostty, aerospace, sketchybar, karabiner, macos,<br>darwin/macos, darwin/homebrew"]
    baseModules["zsh, git, tmux, neovim, packages,<br>ws, agents, secrets, darwin/codex"]
    personalModules["rex"]
    rexServerModules["rex-server"]
  end
  mac --> base & gui & personal
  linux --> base & personal & rexServer
  gui --> guiModules
  base --> baseModules
  personal --> personalModules
  rexServer --> rexServerModules
```

| Role         | Adds                                                  |
| ------------ | ----------------------------------------------------- |
| `base`       | The shell, editor, tools and agent settings           |
| `gui`        | A Mac's window manager, bar, fonts, apps and settings |
| `personal`   | Rex's settings and byor's rules                       |
| `rex-server` | Rex's server, as a systemd user service               |

Some modules also check a second role. `packages`, for example, adds fonts
for `gui`, and pi, Copilot CLI and Python for `personal`. The theme module
applies on every computer.

Rex is the terminal, and tmux, with Ghostty on a Mac, is set up as well for
a computer without Rex. It has the same keys and popups.

## Files

```text
flake.nix           the inputs, and the configs each computer gets
hosts/              each computer's roles and settings
modules/
  options.nix       the options a host file sets
  home/             one file per program, for Home Manager
  darwin/           macOS settings, Homebrew casks and /etc/codex, for nix-darwin
  codex-managed.nix the files Codex's managed hooks need in /etc/codex
theme/              what each color means, one file per app, and `theme`
pkgs/               ws's Go source and the pair package
config/             files programs read as they are, linked from the checkout
ai-harness/         the agents' instructions, skills and hooks
secrets/            secrets.yaml, encrypted to the keys in .sops.yaml
tests/              the prompt's test, and a placeholder work host CI builds
docs/               these pages
assets/             the README's screenshots, and retake.sh, which retakes them
```

Most files under `config/` and `ai-harness/` are links into the checkout,
so a program picks up an edit when it next starts or reloads. A switch
writes everything else, and also reads a few files from those two folders
as it builds. [AGENTS.md](../AGENTS.md#applying-a-change) names them and
says which switch each folder needs.
