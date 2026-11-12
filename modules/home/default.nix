{ config, pkgs, ... }:
{
  imports = [
    ./packages.nix
    ./theme.nix
    ./zsh.nix
    ./git.nix
    ./tmux.nix
    ./neovim.nix
    ./rex.nix
    ./rex-server.nix
    ./ws.nix
    ./agents.nix
    ./secrets.nix
    ./ghostty.nix
    ./aerospace.nix
    ./karabiner.nix
    ./sketchybar.nix
    ./macos.nix
  ];

  home = {
    username = config.dotfiles.user;
    homeDirectory =
      (if pkgs.stdenv.hostPlatform.isDarwin then "/Users/" else "/home/") + config.dotfiles.user;
    stateVersion = "26.05";
  };

  programs.home-manager.enable = true;
}
