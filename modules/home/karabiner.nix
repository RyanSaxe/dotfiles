# Karabiner-Elements' config. The cask in modules/darwin/homebrew.nix
# installs the app. The whole folder links to the checkout, because
# Karabiner rewrites karabiner.json when a setting changes.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles;
in
lib.mkIf (lib.elem "personal" cfg.roles && pkgs.stdenv.hostPlatform.isDarwin) {
  xdg.configFile."karabiner".source =
    config.lib.file.mkOutOfStoreSymlink "${cfg.repo}/config/karabiner";
}
