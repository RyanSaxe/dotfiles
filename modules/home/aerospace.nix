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
in
lib.mkIf (lib.elem "gui" cfg.roles && pkgs.stdenv.hostPlatform.isDarwin) {
  programs.aerospace = {
    enable = true;
    launchd.enable = true;
    settings = lib.recursiveUpdate toml ({
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
    });
  };
}
