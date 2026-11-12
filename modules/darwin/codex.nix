# Codex reads its managed hooks from /etc/codex. This writes the files
# modules/codex-managed.nix lists there.
{ config, lib, ... }:
lib.mkIf (lib.elem "base" config.dotfiles.roles) {
  environment.etc = lib.mapAttrs' (
    name: source: lib.nameValuePair "codex/${name}" { inherit source; }
  ) (import ../codex-managed.nix config.dotfiles.repo);
}
