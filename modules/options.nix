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

    ws.agent = mkOption {
      type = types.enum [
        "claude"
        "codex"
        "agy"
      ];
      default = if lib.elem "personal" config.dotfiles.roles then "claude" else "codex";
      defaultText = lib.literalExpression ''if lib.elem "personal" config.dotfiles.roles then "claude" else "codex"'';
      description = "The agent CLI ws starts on this computer. Its model and effort are the CLI's own settings, which agents.nix sets.";
    };

    ws.openAs = mkOption {
      type = types.enum [
        "tab"
        "session"
      ];
      default = "tab";
      description = "How ws opens a worktree: as a tab named after it in its project's session, or as a session of its own.";
    };

    desktopPicture = mkOption {
      type = types.bool;
      default = true;
      description = "Whether `theme` sets the desktop picture on a computer with the gui role. A computer whose desktop picture is managed elsewhere turns it off.";
    };
  };
}
