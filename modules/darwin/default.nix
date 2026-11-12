{ config, ... }:
let
  inherit (config.dotfiles) user;
in
{
  imports = [
    ./macos.nix
    ./homebrew.nix
    ./codex.nix
  ];

  # Determinate's installer owns Nix itself, so nix-darwin leaves it alone.
  nix.enable = false;

  system.primaryUser = user;
  users.users.${user}.home = "/Users/${user}";

  # Puts Nix on zsh's path. home-manager writes the real zsh config, so
  # the system one skips its own completion and prompt.
  programs.zsh = {
    enable = true;
    enableCompletion = false;
    enableBashCompletion = false;
    promptInit = "";
  };

  system.stateVersion = 7;
}
