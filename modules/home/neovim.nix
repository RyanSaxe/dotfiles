# Neovim with LazyVim. The config is config/nvim, linked from the
# checkout so lazy.nvim can write its lock file and an edit applies the
# next time Neovim starts. Its language servers come from packages.nix.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles;
in
lib.mkIf (lib.elem "base" cfg.roles) {
  home.packages = [ pkgs.neovim ];
  xdg.configFile."nvim".source = config.lib.file.mkOutOfStoreSymlink "${cfg.repo}/config/nvim";
}
