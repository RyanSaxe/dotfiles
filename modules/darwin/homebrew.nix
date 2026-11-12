# Homebrew installs the apps nixpkgs has no Mac build of, or whose vendor
# ships them through Homebrew. A Mac switch installs what's listed here
# and leaves every other formula and cask as it is.
{ config, lib, ... }:
lib.mkIf (lib.elem "gui" config.dotfiles.roles) {
  homebrew = {
    enable = true;
    user = config.dotfiles.user;
    onActivation.cleanup = "none";
    casks = [
      # OpenAI's cask, which offers its own upgrades.
      "codex"
      "docker-desktop"
      "libreoffice"
    ]
    # Its config is config/karabiner, linked by modules/home/karabiner.nix.
    ++ lib.optional (lib.elem "personal" config.dotfiles.roles) "karabiner-elements";
  };
}
