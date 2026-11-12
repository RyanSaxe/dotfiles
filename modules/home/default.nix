{
  config,
  lib,
  pkgs,
  ...
}:
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

  # A Linux box runs another distribution, not NixOS. Nix's installer adds
  # its paths only for interactive shells, so this has every zsh, including
  # `ssh box CMD`, load them from the session variables. The box has no
  # screen, so the GPU driver setup stays off.
  targets.genericLinux = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
    enable = true;
    gpu.enable = false;
  };
}
