# AeroSpace, from config/aerospace/aerospace.toml with the built-in display's
# notch applied. home-manager's launchd agent starts it at login.
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
  # A MacBook with a notch keeps the top 32 points of its built-in display
  # out of the area AeroSpace lays windows out in, at the default display
  # scaling. A Mac without a built-in display has no monitor this matches.
  notch = 32;
  ws = pkgs.callPackage ../../pkgs/ws { };
  # rex lives inside Rex Server's app, as in modules/home/ws.nix.
  rexDir = "${config.home.homeDirectory}/Library/Application Support/com.superlogical.rex/RexServer/Versions/Current/Rex Server.app/Contents/MacOS";
in
lib.mkIf (lib.elem "gui" cfg.roles && pkgs.stdenv.hostPlatform.isDarwin) {
  # launchd throttles an agent that names no ProcessType to utility priority,
  # along with every program it starts. While the Mac was busy, AeroSpace
  # then took up to a second to answer a command, and Cmd-Alt-A's ws focus
  # ran at that priority too.
  launchd.agents.aerospace.config.ProcessType = "Interactive";
  programs.aerospace = {
    enable = true;
    launchd.enable = true;
    settings = lib.recursiveUpdate toml {
      gaps.outer.top = [
        { monitor.built-in = top - notch; }
        top
      ];
      # launchd starts AeroSpace without the Nix profile on PATH, so the
      # workspace-change callback could not find sketchybar.
      exec.env-vars.PATH = "${config.home.profileDirectory}/bin:\${PATH}";
      # Cmd-Alt-A, T and R bring Rex, or Ghostty on tmux where Rex isn't
      # installed, onto the code workspace, then go to the agent that needs
      # you or open the Inbox on its Tasks tabs or on Needs you. ws switches
      # to the code workspace itself after checking what had focus, so
      # Cmd-Alt-A from another workspace doesn't treat Rex's background
      # session as already looked at.
      mode.main.binding =
        lib.mapAttrs (_: what: "exec-and-forget PATH='${rexDir}':$PATH ${ws}/bin/ws focus ${what}")
          {
            cmd-alt-a = "agent";
            cmd-alt-t = "tasks";
            cmd-alt-r = "reviews";
          };
    };
  };
}
