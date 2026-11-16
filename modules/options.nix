# Options every host file sets. Both the Mac config and the home config
# import this, so a host file can be shared by the two.
{ config, lib, ... }:
let
  inherit (lib) mkOption types;
in
{
  options.dotfiles = {
    host = mkOption {
      type = types.str;
      description = "This computer's name in the flake that builds it, which the switch commands build.";
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
          "rex-server"
        ]
      );
      description = "What this computer is for. Each module checks the roles it belongs to.";
    };

    repo = mkOption {
      type = types.str;
      description = "Where this repository is checked out. Linked config files point here, so edits apply without a switch.";
    };

    flake = mkOption {
      type = types.str;
      default = config.dotfiles.repo;
      description = "The folder of the flake that builds this computer, which the switch commands build and nix-update updates. A computer built from a private flake sets it to that flake's folder.";
    };

    secretsFile = mkOption {
      type = types.path;
      default = ../secrets/secrets.yaml;
      description = "The sops file each home switch decrypts this computer's secrets from. A computer built from a private flake can bring its own.";
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

    vault = mkOption {
      type = types.nullOr (
        types.submodule {
          options = {
            dir = mkOption {
              type = types.str;
              description = "Where the vault is checked out, which the switch exports as VAULT_DIR.";
            };
            remote = mkOption {
              type = types.str;
              description = "The git remote the home switch clones the vault from when its folder is missing.";
            };
          };
        }
      );
      default = null;
      description = "The Markdown vault that Neovim and ws read and write, or null for a computer without one.";
    };

    claudeCode = mkOption {
      type = types.bool;
      default = true;
      description = "Whether this computer has Claude Code. Without it, a switch writes none of Claude Code's files or settings.";
    };
  };
}
