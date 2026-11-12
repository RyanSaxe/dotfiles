# sketchybar, with its scripts linked from the checkout.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles;
in
lib.mkIf (lib.elem "gui" cfg.roles && pkgs.stdenv.hostPlatform.isDarwin) {
  # The whole folder is linked, so the module writes no sketchybarrc.
  xdg.configFile."sketchybar".source =
    config.lib.file.mkOutOfStoreSymlink "${cfg.repo}/config/sketchybar";

  programs.sketchybar = {
    enable = true;
    # The workspace scripts call aerospace.
    extraPackages = [ pkgs.aerospace ];
    service.enable = true;
  };
}
