# Working in this repository

This repository configures Ryan's computers with Nix. README.md describes the
roles and the layout.

## Applying a change

What an edit needs depends on where it is:

- **No command:** most files under `config/` and `ai-harness/` are linked
  from this checkout. A program picks up the edit when it next starts or
  reloads. Rex needs `rex config reload` and tmux needs `prefix r`.
- **`home-switch`:** everything in `modules/home/`, `theme/`, `pkgs/` and
  `secrets/`, including new tools. A home switch also reads these files from
  the linked folders as it builds, so they need it too:
  `config/aerospace/aerospace.toml`, `config/zsh/starship.toml`, the
  shaders in `config/ghostty/shaders`, and `ai-harness/AGENTS.md`, whose
  text Codex gets from its settings. It needs no password, so run it
  yourself and check the result in the program.
- **`mac-switch`:** `modules/darwin/` (macOS settings, the Homebrew casks and
  `/etc/codex`), `modules/codex-managed.nix`, and
  `ai-harness/codex/requirements.toml`, which a Mac switch copies into
  `/etc/codex`. On Linux, a home switch applies those two files. A Mac
  switch asks for Ryan's password, so stop and give him the command.
- **Both:** `flake.nix`, `flake.lock`, `hosts/` and `modules/options.nix`
  reach every config, so a Mac needs both switches.

Light and dark need no switch: `theme light` or `theme dark` flips macOS and
every app at once. ws keeps its mascot in `~/.local/state/ws/mascot.json`,
outside this repository, and rewrites it itself.

To color a new app, add a file to `theme/apps` that turns the meanings in
`theme/meanings.nix`, such as `t.muted` or `t.code.function`, into the
files the app reads. Never write a hex there. Each home switch renders every
file in `theme/apps` for both modes, and `theme` points `~/.config/theme`
at the current one. An app that reads its file when it runs needs nothing
more. One that keeps its colors in memory also needs a reload line in
`theme/theme.sh`.

A Mac switch installs the casks `modules/darwin/homebrew.nix` lists. It
leaves every other Homebrew formula and cask as it is.

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

- Use the role a setting belongs to. Check a role with
  `lib.elem "ROLE" config.dotfiles.roles`.
- Install tools through Nix. Use Homebrew for a Mac app that nixpkgs has no
  Mac build of, or that its vendor ships as a cask, as Codex and Karabiner
  are.
- Prefer small code of our own, then tools from established maintainers.
  Avoid community plugins and flakes unless nothing else works.
- Never decrypt a secret into a file outside `~/.config/sops-nix`, and never
  commit an age private key.
