# Setup

Each computer keeps its checkout at `~/generic/dotfiles`, where its host
file expects it. These steps set up the two computers `flake.nix` lists,
`mac` and `linux`.

## A Mac

1. Install Nix, Homebrew and Claude Code. The Mac switch installs apps
   through Homebrew but can't install Homebrew itself, and Claude Code goes
   before the first home switch so that the switch sets byor and pair up
   for it.

   ```sh
   curl -fsSL https://install.determinate.systems/nix | sh -s -- install
   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
   curl -fsSL https://claude.ai/install.sh | bash
   ```

2. In a new terminal, so that `nix` is on the PATH, clone the `v2` branch
   and make the age key that opens the secrets:

   ```sh
   nix run nixpkgs#git -- clone -b v2 https://github.com/RyanSaxe/dotfiles ~/generic/dotfiles
   mkdir -p ~/Library/Application\ Support/sops/age
   nix shell nixpkgs#age -c age-keygen -o ~/Library/Application\ Support/sops/age/keys.txt
   ```

3. [Encrypt the secrets to the new key](#encrypt-the-secrets-to-a-new-key).

4. Pull, run the first switches and sign gh in to GitHub, which git and
   Reviews use:

   ```sh
   nix run nixpkgs#git -- -C ~/generic/dotfiles pull
   sudo nix run nix-darwin/master#darwin-rebuild -- switch --flake ~/generic/dotfiles#mac
   nix run home-manager/master -- switch -b pre-nix --flake ~/generic/dotfiles#ryansaxe@mac
   gh auth login
   ```

   `-b pre-nix` renames each file the home switch would replace, such as an
   old `~/.zshrc`, to `NAME.pre-nix`.

Rex, Tailscale and Google Chrome are still installed by hand, as
[LATER.md](../LATER.md) says.

## A Linux box

There's no Linux machine yet, so CI builds its config on every push to keep it
working until there is one.

The steps match the Mac's, without Homebrew, Claude Code's installer or
nix-darwin. The home switch installs Claude Code and Codex from nixpkgs,
and runs Rex's server as a systemd user service.

1. Install Nix:

   ```sh
   curl -fsSL https://install.determinate.systems/nix | sh -s -- install
   ```

2. In a new terminal, clone the `v2` branch and make the age key:

   ```sh
   nix run nixpkgs#git -- clone -b v2 https://github.com/RyanSaxe/dotfiles ~/generic/dotfiles
   mkdir -p ~/.config/sops/age
   nix shell nixpkgs#age -c age-keygen -o ~/.config/sops/age/keys.txt
   ```

3. [Encrypt the secrets to the new key](#encrypt-the-secrets-to-a-new-key).

4. Pull, run the first home switch, then do once by hand what Home Manager
   can't: change the login shell and write to `/etc`.

   ```sh
   nix run nixpkgs#git -- -C ~/generic/dotfiles pull
   nix run home-manager/master -- switch -b pre-nix --flake ~/generic/dotfiles#ryansaxe@linux
   gh auth login
   echo ~/.nix-profile/bin/zsh | sudo tee -a /etc/shells   # make zsh the login shell
   sudo chsh -s ~/.nix-profile/bin/zsh "$USER"
   sudo ln -sfn ~/.config/codex/managed /etc/codex          # give Codex its managed hooks
   loginctl enable-linger                                   # keep Rex's server running while logged out
   rex server status                                        # print the link that signs the server in to the tailnet
   ```

## Encrypt the secrets to a new key

A new key can't open the secrets until they're encrypted to it.
`age-keygen` prints the public key. On a computer whose key `.sops.yaml`
already lists, add the new public key to `.sops.yaml`, then:

```sh
sops updatekeys secrets/secrets.yaml
git commit .sops.yaml secrets/secrets.yaml -m "chore(secrets): add a key"
git push
```

## After the first switches

```sh
home-switch   # apply a change to the home config
mac-switch    # apply a change to macOS
nix-update    # update the flake's inputs, run the switches, upgrade uv's tools
```

[AGENTS.md](../AGENTS.md#applying-a-change) says which change needs which
switch.

## Another computer

A new computer needs its own host file in `hosts/`, an entry in
`flake.nix`, and its own lines under `pair-hub-host` and `attention-watch`
in the secrets.
