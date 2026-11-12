# Options every host file sets. Both the Mac config and the home config
# import this, so a host file can be shared by the two.
{ lib, ... }:
let
  inherit (lib) mkOption types;
in
{
  options.dotfiles = {
    host = mkOption {
      type = types.str;
      description = "This computer's name in flake.nix, which the switch commands build.";
    };

    user = mkOption {
      type = types.str;
      description = "The account name on this computer.";
    };

    roles = mkOption {
      type = types.listOf (
        types.enum [
          "base"
          "gui"
          "personal"
          "work"
        ]
      );
      description = "What this computer is for. Each module checks the roles it belongs to.";
    };

    repo = mkOption {
      type = types.str;
      description = "Where this repository is checked out. Linked config files point here, so edits apply without a switch.";
    };

    git.email = mkOption {
      type = types.str;
      description = "The email git commits with on this computer.";
    };

    notchInset = mkOption {
      type = types.int;
      default = 0;
      description = "Points AeroSpace leaves above the windows on the built-in display, for the notch and the bar.";
    };
  };
}
