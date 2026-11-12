{ config, pkgs, ... }:
{
  imports = [
    ./packages.nix
    ./git.nix
    ./secrets.nix
  ];

  home = {
    username = config.dotfiles.user;
    homeDirectory =
      (if pkgs.stdenv.hostPlatform.isDarwin then "/Users/" else "/home/") + config.dotfiles.user;
    stateVersion = "26.05";
  };

  programs.home-manager.enable = true;
}
