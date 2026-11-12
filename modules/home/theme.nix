# Installs every app's theme files for both modes, into ~/.config/theme/dark
# and light, and `theme`, which points the links beside them at one mode.
# macOS's appearance picks the mode, and each switch runs `theme` to follow
# it.
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  files =
    mode:
    lib.mapAttrs' (name: text: lib.nameValuePair "theme/${mode}/${name}" { inherit text; }) (
      import ../../theme {
        inherit lib mode;
        palette = inputs.catppuccin-palette;
      }
    );
  theme = pkgs.writeShellApplication {
    name = "theme";
    runtimeInputs = [ pkgs.tmux ];
    text = builtins.readFile ../../theme/theme.sh;
  };
  # The activation's PATH has no sketchybar, so `theme` is told where it is.
  sketchybar = lib.optionalString config.programs.sketchybar.enable "SKETCHYBAR=${config.programs.sketchybar.finalPackage}/bin/sketchybar";
in
lib.mkMerge [
  {
    home.packages = [ theme ];
    xdg.configFile = files "dark" // files "light";
    home.activation.theme = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      ${sketchybar} run ${theme}/bin/theme
    '';
  }

  # sketchybar runs `theme` whenever macOS's appearance changes.
  (lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
    programs.sketchybar.extraPackages = [ theme ];
  })
]
