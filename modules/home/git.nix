{ config, lib, ... }:
let
  cfg = config.dotfiles;
in
lib.mkIf (lib.elem "base" cfg.roles) {
  programs.git = {
    enable = true;
    ignores = [
      "**/*.local.*"
      "TODO.local/"
      "TASKS/"
      "SPECS/"
      "tasks/"
      "specs/"
    ];
    settings = {
      user = {
        name = "Ryan Saxe";
        inherit (cfg.git) email;
      };
      core = {
        editor = "nvim";
        autocrlf = "input";
      };
      push = {
        default = "simple";
        autoSetupRemote = true;
      };
      pull.rebase = true;
      branch.autosetuprebase = "always";
      init.defaultBranch = "main";
      alias = {
        co = "checkout";
        br = "branch";
        ci = "commit";
        st = "status";
        unstage = "reset HEAD --";
        last = "log -1 HEAD";
        lg = "log --oneline --graph --decorate --all";
        ddiff = "-c delta.side-by-side=true diff";
        dshow = "-c delta.side-by-side=true show";
      };
      merge = {
        conflictStyle = "zdiff3";
      };
      status.showUntrackedFiles = "all";
    };
  };

  programs.delta = {
    enable = true;
    enableGitIntegration = true;
    options.navigate = true;
  };

  programs.gh = {
    enable = true;
    gitCredentialHelper.enable = true;
    settings = {
      git_protocol = "https";
      aliases.co = "pr checkout";
    };
  };
}
