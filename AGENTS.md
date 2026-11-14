# Working in this repository

This repository sets up the user's computers with one Nix flake.
`docs/layout.md` describes the hosts, roles and where each file lives.

## Applying a change

How a change takes effect depends on the file:

- **No command:** most files under `config/` and `ai-harness/` are links
  into this checkout, so a program picks up an edit when it next starts or
  reloads. Reload Rex with `rex config reload` and tmux with `prefix r`.
- **`home-switch`:** files in `modules/home/`, `theme/`, `pkgs/` and
  `secrets/`, including new tools. The build also reads four linked files,
  so they need it too: `config/aerospace/aerospace.toml`,
  `config/zsh/starship.toml`, the shaders in `config/ghostty/shaders`, and
  `ai-harness/AGENTS.md`, which the build writes into Codex's settings.
  `home-switch` needs no password, so run it yourself and check the result
  in the program.
- **`mac-switch`:** `modules/darwin/` (macOS settings, the Homebrew casks
  and `/etc/codex`), `modules/codex-managed.nix`, and
  `ai-harness/codex/requirements.toml`, which `mac-switch` copies into
  `/etc/codex`. On Linux, `home-switch` applies those two files instead.
  `mac-switch` asks for the user's password, so stop and give the user the
  command to run.
- **Both:** `flake.nix`, `flake.lock`, `hosts/` and `modules/options.nix`
  affect every config, so a Mac needs `home-switch` and `mac-switch`.

`theme light` and `theme dark` switch macOS and every app between light and
dark without a rebuild. ws keeps its mascot in
`~/.local/state/ws/mascot.json`, outside this repository, and rewrites that
file itself.

To color a new app, add a file to `theme/apps` that maps the meanings in
`theme/meanings.nix`, such as `t.muted` or `t.code.function`, to the files
the app reads. Never write a hex color there. Each `home-switch` renders
every file in `theme/apps` for both modes, and `theme` points
`~/.config/theme` at the current mode. An app that reads its file when it
runs needs nothing more. An app that keeps its colors in memory also needs a
reload line in `theme/theme.sh`.

`mac-switch` installs the casks listed in `modules/darwin/homebrew.nix` and
leaves every other Homebrew formula and cask alone.

## Checks

Run `prek run --all-files` before committing. Build both of the Mac's configs
before calling a change done:

```sh
nix build --no-link .#darwinConfigurations.mac.system \
  '.#homeConfigurations."ryansaxe@mac".activationPackage'
```

CI also builds the Linux home config, on Ubuntu. When a change reaches
Linux, evaluate that config on the Mac before pushing:

```sh
nix eval --raw '.#homeConfigurations."ryansaxe@linux".activationPackage.drvPath'
```

## Rules

- Put each setting under the role it belongs to. Check a role with
  `lib.elem "ROLE" config.dotfiles.roles`.
- Install tools through Nix. Use Homebrew only for a Mac app that nixpkgs
  has no Mac build of, or that its vendor ships as a cask, as Codex and
  Karabiner are.
- Prefer a little code in this repository, then tools from established
  maintainers. Avoid community plugins and flakes unless nothing else works.
- Never decrypt a secret into a file outside `~/.config/sops-nix`, and never
  commit an age private key.
