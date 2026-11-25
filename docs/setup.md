# Setup

Clone this repository at `~/generic/dotfiles`, where every host file expects it.
These steps bootstrap `mac` and `linux` from `flake.nix`.

## A Mac

1. Install Nix, Homebrew, and (on `personal` hosts) Claude Code before the first
   switch so the switch can configure `byor` and `pair` for it. (`home-switch`
   installs Antigravity CLI itself on `personal` hosts.)

   ```sh
   curl -fsSL https://install.determinate.systems/nix | sh -s -- install
   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
   curl -fsSL https://claude.ai/install.sh | bash   # personal hosts only
   ```

2. Open a new terminal (so `nix` is on `PATH`), clone the repo and generate the
   age key for `sops`:

   ```sh
   nix run nixpkgs#git -- clone https://github.com/RyanSaxe/dotfiles ~/generic/dotfiles
   mkdir -p ~/Library/Application\ Support/sops/age
   nix shell nixpkgs#age -c age-keygen -o ~/Library/Application\ Support/sops/age/keys.txt
   ```

3. [Encrypt the secrets to the new key](#encrypt-the-secrets-to-a-new-key).

4. Pull, run the first switches and authenticate `gh` (used by git and Inbox):

   ```sh
   nix run nixpkgs#git -- -C ~/generic/dotfiles pull
   sudo nix run nix-darwin/master#darwin-rebuild -- switch --flake ~/generic/dotfiles#mac
   nix run home-manager/master -- switch -b pre-nix --flake ~/generic/dotfiles#ryansaxe@mac
   gh auth login
   ```

   `-b pre-nix` backs up existing files (such as `~/.zshrc`) as `NAME.pre-nix`.
   `home-switch` also [clones the vault](#the-vault).

Rex, Tailscale and Google Chrome are installed manually (see
[LATER.md](../LATER.md)). Finish with [By hand](manual.md) for Chrome's theme
and agent logins.

## A Linux box

CI builds the Linux home config on every push to keep it working. Unlike a Mac,
Linux uses Home Manager only: `home-switch` installs Codex from nixpkgs,
Antigravity CLI from its official installer on `personal` hosts, and Rex's
server as a systemd user service.

1. Install Nix, and (on `personal` hosts) Claude Code:

   ```sh
   curl -fsSL https://install.determinate.systems/nix | sh -s -- install
   curl -fsSL https://claude.ai/install.sh | bash   # personal hosts only
   ```

2. Open a new terminal, clone the repo and generate the age key:

   ```sh
   nix run nixpkgs#git -- clone https://github.com/RyanSaxe/dotfiles ~/generic/dotfiles
   mkdir -p ~/.config/sops/age
   nix shell nixpkgs#age -c age-keygen -o ~/.config/sops/age/keys.txt
   ```

3. [Encrypt the secrets to the new key](#encrypt-the-secrets-to-a-new-key).

4. Pull, run the first `home-switch`, then apply the one-time system steps Home
   Manager cannot do:

   ```sh
   nix run nixpkgs#git -- -C ~/generic/dotfiles pull
   nix run home-manager/master -- switch -b pre-nix --flake ~/generic/dotfiles#ryansaxe@linux
   gh auth login
   echo ~/.nix-profile/bin/zsh | sudo tee -a /etc/shells   # register zsh
   sudo chsh -s ~/.nix-profile/bin/zsh "$USER"             # set login shell
   sudo ln -sfn ~/.config/codex/managed /etc/codex         # Codex managed hooks
   loginctl enable-linger                                  # keep Rex server running when logged out
   rex server status                                       # print tailnet sign-in link
   ```

   `home-switch` also [clones the vault](#the-vault).

## Encrypt the secrets to a new key

`age-keygen` prints the new public key. On a machine already listed in
`.sops.yaml`, add that public key to `.sops.yaml` and re-encrypt:

```sh
sops updatekeys secrets/secrets.yaml
git commit .sops.yaml secrets/secrets.yaml -m "chore(secrets): add a key"
git push
```

## The vault

`home-switch` clones the Markdown notes vault into `~/generic/vault` over SSH
when the directory is missing. If this machine's SSH key is not on GitHub yet,
the switch logs a notice and finishes the rest; re-run `home-switch` after adding
the key.

## After the first switches

```sh
home-switch   # apply home config changes
mac-switch    # apply macOS, Homebrew and /etc changes
nix-update    # update flake inputs, run switches, upgrade uv tools and agy
```

See [AGENTS.md](../AGENTS.md#applying-a-change) for which files need which
switch.

## Another computer

Add a host file under `hosts/`, register it in `flake.nix`, and add host entries
under `pair-hub-host`, `attention-watch` and `attention-ignore` in
`secrets/secrets.yaml`.

Set `vault` in the host file to clone and enable the vault; omit it to leave
`$VAULT_DIR` unset (Neovim skips `obsidian.nvim` and the Inbox Tasks tab reports
no vault). For machines whose details must stay private, use a private flake
below.

## A computer built from a private flake

A private flake keeps account names, emails and private tools out of this public
repo. It takes this checkout as input `dotfiles`, stores its own `host.nix` and
`secrets.yaml`, and calls `dotfiles.lib.mac` / `dotfiles.lib.home`:

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
    desktopPicture = false; # managed elsewhere
    vault = {
      dir = "/Users/ACCOUNT/generic/vault";
      remote = "git@github.com:GITHUB_ACCOUNT/vault.git";
    };
  };
}
```

- `name` must match the output names so `mac-switch` builds `work` and
  `home-switch` builds `ACCOUNT@work`. Linux hosts define only
  `homeConfigurations` with `system = "x86_64-linux"`, `/home` paths and no
  `gui` role.
- `flake` points the switches and `nix-update` at the private flake. The
  switches override the `dotfiles` input with the local checkout (including
  uncommitted edits), so the input must be named `dotfiles`. `?ref=main` lets
  Nix lock a dirty checkout; `nix-update` updates the private lock while keeping
  shared inputs pinned to this repo's `flake.lock`.
- `secretsFile` needs `pushover-user`, `pushover-token`, and a host entry (here
  `work`) under `pair-hub-host`, `attention-watch` and `attention-ignore`
  (unused values may be empty). Add a `.sops.yaml` beside it:

  ```yaml
  # .sops.yaml
  creation_rules:
    - path_regex: secrets\.yaml$
      age: AGE_PUBLIC_KEY
  ```

  Create it with `sops secrets.yaml`, then commit every file in the private
  flake (Nix ignores untracked files).

Bootstrap as a Mac or Linux box above, skipping the Rex steps on Linux hosts
without `rex-server`, and run the first switches against the private flake:

```sh
sudo nix run nix-darwin/master#darwin-rebuild -- switch --flake ~/generic/work-dotfiles#work
nix run home-manager/master -- switch -b pre-nix --flake ~/generic/work-dotfiles#ACCOUNT@work
```

### Steps that need a person at the keyboard

An agent can automate the rest, but needs you for:

- `sudo` passwords during the Nix installer and `mac-switch`;
- `gh auth login` and `gh ssh-key add ~/.ssh/id_ed25519.pub` (needed to clone
  the vault);
- secret values: Pushover keys (`sops -d secrets/secrets.yaml` on an existing
  host) and the GitHub accounts to watch/ignore in Inbox.
