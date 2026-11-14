{ config, lib, ... }:
let
  cfg = config.dotfiles;
in
lib.mkIf (lib.elem "base" cfg.roles) {
  programs.git = {
    enable = true;
    # agent-notes/ holds agents' plans and scratch files in any repository.
    # TODO.local/ is its older name, which some clones still have.
    ignores = [
      "**/*.local.*"
      "agent-notes/"
      "TODO.local/"
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
      diff.tool = "codediff";
      difftool.codediff.cmd = ''nvim -c "CodeDiff file $LOCAL $REMOTE"'';
      merge = {
        tool = "codediff";
        conflictStyle = "zdiff3";
      };
      mergetool.codediff = {
        cmd = ''nvim -c "CodeDiff merge $MERGED"'';
        trustExitCode = true;
      };
      status.showUntrackedFiles = "all";
    };
  };

  programs.delta = {
    enable = true;
    enableGitIntegration = true;
    # delta takes bat's theme from BAT_THEME, which the shell sets to the
    # current mode's.
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

  # Dotfiles.tmTheme for each mode, which bat and delta share. bat picks
  # one from macOS's appearance, and a shell's BAT_THEME names the same.
  programs.bat = {
    enable = true;
    config = {
      theme = "auto:system";
      theme-dark = "dotfiles-dark";
      theme-light = "dotfiles-light";
    };
    themes = lib.genAttrs [ "dotfiles-dark" "dotfiles-light" ] (name: {
      src = config.xdg.configFile."theme/${lib.removePrefix "dotfiles-" name}/Dotfiles.tmTheme".source;
    });
  };
}
