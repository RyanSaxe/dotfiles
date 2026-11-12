# ws, and on computers with a screen the watcher behind sketchybar's A and R
# letters.
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  cfg = config.dotfiles;
  ws = pkgs.callPackage ../../pkgs/ws { };
  has = role: lib.elem role cfg.roles;
in
lib.mkMerge [
  (lib.mkIf (has "base") {
    home.packages = [ ws ];
    # The popups turn the mascot's accent into a color with it.
    home.sessionVariables.WS_PALETTE = "${inputs.catppuccin-palette}/palette.json";
  })

  (lib.mkIf (has "gui" && pkgs.stdenv.hostPlatform.isDarwin) {
    launchd.agents.ws-attention = {
      enable = true;
      config = {
        ProgramArguments = [
          "${ws}/bin/ws"
          "attention"
          "--watch"
        ];
        KeepAlive = true;
        RunAtLoad = true;
        # rex lives inside Rex Server's app, and gh and sketchybar in the
        # home profile or Homebrew.
        EnvironmentVariables.PATH = lib.concatStringsSep ":" [
          "${config.home.homeDirectory}/Library/Application Support/com.superlogical.rex/RexServer/Versions/Current/Rex Server.app/Contents/MacOS"
          "${config.home.profileDirectory}/bin"
          "/opt/homebrew/bin"
          "/usr/bin"
          "/bin"
        ];
        StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/ws-attention.log";
      };
    };
  })
]
