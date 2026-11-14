# Ghostty, with its look: the config links from the checkout, the two
# themes are the terminal colors Rex shows too, from theme/apps/terminal.nix,
# and the shaders follow the theme's mode. Ghostty picks the dark or light
# theme by macOS's appearance.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles;
  linkTheme = file: config.lib.file.mkOutOfStoreSymlink "${config.xdg.configHome}/theme/${file}";
  themeFile = mode: config.xdg.configFile."theme/${mode}/ghostty-theme".text;
in
lib.mkIf (lib.elem "gui" cfg.roles && pkgs.stdenv.hostPlatform.isDarwin) {
  home.packages = [ pkgs.ghostty-bin ];

  xdg.configFile = {
    "ghostty/config".source = config.lib.file.mkOutOfStoreSymlink "${cfg.repo}/config/ghostty/config";
    "ghostty/themes/catppuccin-mocha".text = themeFile "dark";
    "ghostty/themes/catppuccin-latte".text = themeFile "light";
    # `theme` points these at one mode and has Ghostty reload them.
    "ghostty/shaders/frame.glsl".source = linkTheme "frame.glsl";
    "ghostty/shaders/cursor_trail.glsl".source = linkTheme "cursor_trail.glsl";
  };
}
