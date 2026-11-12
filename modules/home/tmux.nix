# tmux. The config is config/tmux, linked from the checkout so an edit
# applies at the next reload (prefix r).
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
  home.packages = [ pkgs.tmux ];

  xdg.configFile."tmux".source = config.lib.file.mkOutOfStoreSymlink "${cfg.repo}/config/tmux";
}
