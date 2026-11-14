# AeroSpace, from config/aerospace/aerospace.toml with this computer's
# notch inset applied. home-manager's launchd agent starts it at login.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles;
  toml = builtins.fromTOML (builtins.readFile ../../config/aerospace/aerospace.toml);
  top = toml.gaps.outer.top;
  ws = pkgs.callPackage ../../pkgs/ws { };
  # rex lives inside Rex Server's app, as in modules/home/ws.nix.
  rexDir = "${config.home.homeDirectory}/Library/Application Support/com.superlogical.rex/RexServer/Versions/Current/Rex Server.app/Contents/MacOS";
in
lib.mkIf (lib.elem "gui" cfg.roles && pkgs.stdenv.hostPlatform.isDarwin) {
  programs.aerospace = {
    enable = true;
    launchd.enable = true;
    settings = lib.recursiveUpdate toml {
      gaps.outer.top =
        if cfg.notchInset == 0 then
          top
        else
          [
            { monitor.built-in = top - cfg.notchInset; }
            top
          ];
      # launchd starts AeroSpace without the Nix profile on PATH, so the
      # workspace-change callback could not find sketchybar.
      exec.env-vars.PATH = "${config.home.profileDirectory}/bin:\${PATH}";
      # Cmd-Alt-A, T and R bring Rex, or Ghostty on tmux where Rex isn't
      # installed, onto the code workspace, then go to the agent that needs
      # you or open Tasks or Reviews.
      mode.main.binding =
        lib.mapAttrs
          (_: what: [
            "workspace code"
            "exec-and-forget PATH='${rexDir}':$PATH ${ws}/bin/ws focus ${what}"
          ])
          {
            cmd-alt-a = "agent";
            cmd-alt-t = "tasks";
            cmd-alt-r = "reviews";
          };
    };
  };
}
