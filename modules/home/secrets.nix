# Secrets from secrets/secrets.yaml, encrypted to each computer's age key
# (.sops.yaml lists them). Each switch decrypts them into
# ~/.config/sops-nix/secrets, one file per secret.
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
{
  imports = [ inputs.sops-nix.homeManagerModules.sops ];

  config = lib.mkIf (lib.elem "base" config.dotfiles.roles) {
    sops = {
      age.keyFile =
        if pkgs.stdenv.hostPlatform.isDarwin then
          "${config.home.homeDirectory}/Library/Application Support/sops/age/keys.txt"
        else
          "${config.xdg.configHome}/sops/age/keys.txt";
      defaultSopsFile = ../../secrets/secrets.yaml;
      # The Pushover hook reads these on every computer.
      secrets.pushover-user = { };
      secrets.pushover-token = { };
      # Each computer's Tailscale address, where its pair hub listens.
      secrets.pair-hub-host.key = "pair-hub-host/${config.dotfiles.host}";
      # Repositories whose new items show in Reviews, as owner/name separated
      # by spaces. Each computer's starts empty.
      secrets.attention-watch.key = "attention-watch/${config.dotfiles.host}";
    };
  };
}
