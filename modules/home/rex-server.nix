# Rex's server, kept running as a systemd user service and reachable on
# the tailnet under this computer's name. The rex command comes with it.
{
  config,
  lib,
  inputs,
  ...
}:
let
  cfg = config.dotfiles;
in
{
  imports = [ inputs.rex.homeManagerModules.default ];

  config = lib.mkIf (lib.elem "rex-server" cfg.roles) {
    services.rex = {
      enable = true;
      tailscale = {
        enable = true;
        hostname = cfg.host;
      };
    };

    # Rex adds its ssh guard to ~/.ssh/config, which Home Manager writes
    # only with this on. The guard is what lets Rex fall back to ssh.
    programs.ssh = {
      enable = true;
      enableDefaultConfig = false;
    };
  };
}
