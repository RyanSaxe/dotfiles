# Homebrew installs the apps nixpkgs has no Mac build of, or whose vendor
# ships them through Homebrew. A Mac switch installs what's listed here
# and leaves every other formula and cask as it is.
{ config, lib, ... }:
let
  has = role: lib.elem role config.dotfiles.roles;
in
lib.mkIf (has "base" || has "gui") {
  homebrew = {
    enable = true;
    user = config.dotfiles.user;
    onActivation.cleanup = "none";
    casks =
      lib.optionals (has "base") [
        # OpenAI's cask, which offers its own upgrades.
        "codex"
      ]
      # Its config is config/karabiner, linked by modules/home/karabiner.nix.
      ++ lib.optional (has "gui") "karabiner-elements";
  };
}
