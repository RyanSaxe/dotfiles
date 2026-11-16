# Setup

Each computer keeps its checkout at `~/generic/dotfiles`, where its host
file expects it. These steps set up the two computers `flake.nix` lists,
`mac` and `linux`.

## A Mac

1. Install Nix and Homebrew, and Claude Code on a computer that uses
   Claude. The Mac switch installs apps through Homebrew but can't install
   Homebrew itself. Claude Code goes before the first home switch, so that
   the switch sets byor and pair up for it.

   ```sh
   curl -fsSL https://install.determinate.systems/nix | sh -s -- install
   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
   curl -fsSL https://claude.ai/install.sh | bash   # only on a computer that uses Claude
   ```

2. In a new terminal, so that `nix` is on the PATH, clone the repository
   and make the age key that opens the secrets:

   ```sh
   nix run nixpkgs#git -- clone https://github.com/RyanSaxe/dotfiles ~/generic/dotfiles
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
   old `~/.zshrc`, to `NAME.pre-nix`. The home switch also
   [clones the vault](#the-vault).

Rex, Tailscale and Google Chrome are still installed by hand, as
[LATER.md](../LATER.md) says. [By hand](manual.md) lists what to do once
after the switches: Chrome's theme and the agents' sign-ins.

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

2. In a new terminal, clone the repository and make the age key:

   ```sh
   nix run nixpkgs#git -- clone https://github.com/RyanSaxe/dotfiles ~/generic/dotfiles
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

   The home switch also [clones the vault](#the-vault).

## Encrypt the secrets to a new key

A new key can't open the secrets until they're encrypted to it.
`age-keygen` prints the public key. On a computer whose key `.sops.yaml`
already lists, add the new public key to `.sops.yaml`, then:

```sh
sops updatekeys secrets/secrets.yaml
git commit .sops.yaml secrets/secrets.yaml -m "chore(secrets): add a key"
git push
```

## The vault

The home switch clones the vault, the Markdown notes that Neovim and ws
read, into `~/generic/vault` when that folder is missing. It clones from
GitHub over ssh, so GitHub must accept this computer's ssh key. Until it
does, the switch prints that it didn't clone the vault and finishes the
rest. Run `home-switch` again once the key is on GitHub.

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
`flake.nix`, and its own lines under `pair-hub-host`, `attention-watch` and
`attention-ignore` in the secrets.

The host file's `vault` names the vault's folder and the git remote to
clone it from. A computer without the vault leaves it out. It then has no
`VAULT_DIR`, so Neovim skips obsidian.nvim and ws's Tasks says the vault
isn't set up.

A computer whose details stay out of this repository is built from a
private flake instead, as the next section shows.

## A computer built from a private flake

A private flake keeps a computer's account name, email and own tools out of
this public repository. It takes this checkout as an input, keeps the
computer's host file and secrets beside its `flake.nix`, and builds the
computer's configs with `lib.mac` and `lib.home`:

```nix
# flake.nix
{
  inputs.dotfiles.url = "git+file:///Users/ACCOUNT/generic/dotfiles?ref=main";
  outputs =
    { dotfiles, ... }:
    {
      darwinConfigurations.work = dotfiles.lib.mac {
        name = "work";
        system = "aarch64-darwin";
        host = ./host.nix;
      };
      homeConfigurations."ACCOUNT@work" = dotfiles.lib.home {
        name = "work";
        system = "aarch64-darwin";
        host = ./host.nix;
      };
    };
}
```

```nix
# host.nix
{
  dotfiles = {
    user = "ACCOUNT";
    roles = [ "base" "gui" "work" ];
    repo = "/Users/ACCOUNT/generic/dotfiles";
    flake = "/Users/ACCOUNT/generic/work-dotfiles"; # this flake's folder
    git.email = "EMAIL";
    secretsFile = ./secrets.yaml;
    claudeCode = false; # this computer has no Claude Code
    desktopPicture = false; # its desktop picture is managed elsewhere
    vault = {
      dir = "/Users/ACCOUNT/generic/vault";
      remote = "git@github.com:GITHUB_ACCOUNT/vault.git";
    };
  };
}
```

`name` is the computer's name in both outputs, so `mac-switch` builds
`work` and `home-switch` builds `ACCOUNT@work`. A Linux box has only the
`homeConfigurations` entry, with `system = "x86_64-linux"`, paths under
`/home` and no `gui` role.

`flake` points the switches and `nix-update` at the private flake. The
switches build the commit of this repository that the private flake's
`flake.lock` pins, and `nix-update` moves that pin to the latest commit on
the checkout's `main`, so pull the checkout first. The other inputs, such
as nixpkgs, stay where this repository's `flake.lock` pins them. The input
names `main` because Nix won't lock a checkout with uncommitted changes
otherwise. Files linked from `config/` and `ai-harness/` still apply from
the checkout as soon as they change.

`secretsFile` is the private flake's own sops file. It needs
`pushover-user` and `pushover-token`, and an entry named after the
computer, here `work`, under `pair-hub-host`, `attention-watch` and
`attention-ignore`. A value the computer doesn't use can be empty. A
`.sops.yaml` beside it lists the age keys that open it:

```yaml
# .sops.yaml
creation_rules:
  - path_regex: secrets\.yaml$
    age: AGE_PUBLIC_KEY
```

`sops secrets.yaml` then opens a new file in your editor and encrypts it
when you save. Nix reads only the files git tracks in a flake's
repository, so commit all of the private flake's files.

Set the computer up as a Mac or a Linux box above, with the private flake
in the folder `flake` names. Make its secrets file in place of encrypting
this repository's, skip the Rex lines on a Linux box without the
`rex-server` role, and run the first switches against the private flake:

```sh
sudo nix run nix-darwin/master#darwin-rebuild -- switch --flake ~/generic/work-dotfiles#work
nix run home-manager/master -- switch -b pre-nix --flake ~/generic/work-dotfiles#ACCOUNT@work
```
