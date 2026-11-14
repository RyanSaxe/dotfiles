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
  rendered =
    mode:
    import ../../theme {
      inherit lib mode;
      palette = inputs.catppuccin-palette;
    };
  files =
    mode:
    lib.mapAttrs' (name: text: lib.nameValuePair "theme/${mode}/${name}" { inherit text; }) (
      rendered mode
    );
  # Each mode's desktop picture, painted from that mode's desktop.json.
  painter = pkgs.python3.withPackages (ps: [
    ps.numpy
    ps.pillow
  ]);
  picture =
    mode:
    pkgs.runCommand "desktop-${mode}.png" { nativeBuildInputs = [ painter ]; } ''
      python3 ${../../theme/desktop.py} ${
        pkgs.writeText "desktop-${mode}.json" (rendered mode)."desktop.json"
      } $out
    '';
  roles = config.dotfiles.roles;
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
    xdg.configFile =
      files "dark"
      // files "light"
      // {
        # Chrome's theme is a folder that Chrome loads once. Chrome would
        # follow a linked folder to one mode's, so the folder stays put and
        # its manifest links to the current mode's.
        "theme/chrome/manifest.json".source =
          config.lib.file.mkOutOfStoreSymlink "${config.xdg.configHome}/theme/chrome-manifest.json";
      };
    home.activation.theme = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      ${sketchybar} run ${theme}/bin/theme
    '';
  }

  # A personal computer with a screen gets a desktop picture for each mode,
  # which `theme` sets at each switch.
  (lib.mkIf (lib.elem "gui" roles && lib.elem "personal" roles) {
    xdg.configFile = {
      "theme/dark/desktop.png".source = picture "dark";
      "theme/light/desktop.png".source = picture "light";
    };
  })

  # sketchybar runs `theme` whenever macOS's appearance changes.
  (lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
    programs.sketchybar.extraPackages = [ theme ];
  })
]
