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
  cfg = config.dotfiles;
  # A computer with a screen gets a desktop picture for each mode, unless
  # its host turns it off.
  desktopPicture = lib.elem "gui" cfg.roles && cfg.desktopPicture;
  # What a computer leaves out: Claude Code's theme and status line colors
  # without Claude Code, which only a personal computer has, and the
  # picture's colors without a picture.
  absent =
    lib.optionals (!lib.elem "personal" cfg.roles) [
      "claude-theme.json"
      "ai-statusline-colors.js"
    ]
    ++ lib.optional (!desktopPicture) "desktop.json";
  files =
    mode:
    lib.mapAttrs' (name: text: lib.nameValuePair "theme/${mode}/${name}" { inherit text; }) (
      removeAttrs (rendered mode) absent
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
  theme = pkgs.writeShellApplication {
    name = "theme";
    runtimeInputs = [ (pkgs.callPackage ../../pkgs/tmux { }) ];
    text = builtins.readFile ../../theme/theme.sh;
  };
  # The activation's PATH has no sketchybar, so `theme` is told where it is.
  sketchybar = lib.optionalString config.programs.sketchybar.enable "SKETCHYBAR=${config.programs.sketchybar.finalPackage}/bin/sketchybar";
in
lib.mkMerge [
  {
    home.packages = [ theme ];
    # `theme` writes Chrome's theme folder, ~/.config/theme/chrome.
    xdg.configFile = files "dark" // files "light";
    home.activation.theme = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      ${sketchybar} run ${theme}/bin/theme
    '';
  }

  # `theme` sets the current mode's picture at each switch.
  (lib.mkIf desktopPicture {
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
