# Ghostty, with its look: the config links from the checkout, the two
# themes are Rex's Catppuccin themes so both terminals share their colors,
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

  # Rex keeps colors as sRGB fractions, and Ghostty takes hex.
  byte =
    x: lib.fixedWidthString 2 "0" (lib.toLower (lib.toHexString (builtins.floor (x * 255 + 0.5))));
  hex = c: "#${byte c.red}${byte c.green}${byte c.blue}";
  ghosttyTheme =
    p:
    lib.concatStringsSep "\n" (
      lib.imap0 (i: c: "palette = ${toString i}=${hex c}") p.ansi
      ++ [
        "background = ${hex p.background}"
        "foreground = ${hex p.foreground}"
        "cursor-color = ${hex p.cursor}"
        "cursor-text = ${hex p.cursorText}"
        "selection-background = ${hex p.selectionBackground}"
        "selection-foreground = ${hex p.selectionForeground}"
      ]
    )
    + "\n";
  rexThemes = lib.importJSON ../../config/rex/themes.json;
  rexTheme = name: ghosttyTheme (lib.findFirst (t: t.name == name) null rexThemes).palette;
in
lib.mkIf (lib.elem "gui" cfg.roles && pkgs.stdenv.hostPlatform.isDarwin) {
  home.packages = [ pkgs.ghostty-bin ];

  xdg.configFile = {
    "ghostty/config".source = config.lib.file.mkOutOfStoreSymlink "${cfg.repo}/config/ghostty/config";
    "ghostty/themes/catppuccin-mocha".text = rexTheme "Catppuccin Mocha";
    "ghostty/themes/catppuccin-latte".text = rexTheme "Catppuccin Latte";
    # `theme` points these at one mode and has Ghostty reload them.
    "ghostty/shaders/frame.glsl".source = linkTheme "frame.glsl";
    "ghostty/shaders/cursor_trail.glsl".source = linkTheme "cursor_trail.glsl";
  };
}
