# Neovim with LazyVim. The config is config/nvim, linked from the
# checkout so lazy.nvim can write its lock file and an edit applies the
# next time Neovim starts. Its language servers come from packages.nix.
# The templates its vault notes start from are linked the same way.
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
  xdg.configFile."vault/templates" = {
    source = config.lib.file.mkOutOfStoreSymlink "${cfg.repo}/config/vault/templates";
    # A link the old checkout left here would otherwise stop the switch.
    force = true;
  };
}
