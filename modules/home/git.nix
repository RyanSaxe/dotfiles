{ config, lib, ... }:
let
  cfg = config.dotfiles;
in
lib.mkIf (lib.elem "base" cfg.roles) {
  programs.git = {
    enable = true;
    # Agents keep their plans and scratch files in agent-notes/, in any repository.
    ignores = [
      "**/*.local.*"
      "agent-notes/"
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
    includes = [
      # delta's diff colors for the current mode, which `theme` relinks.
      { path = "${config.xdg.configHome}/theme/delta-colors.gitconfig"; }
      # The vault's pre-commit hook runs its check, bin/check, before each commit.
      {
        condition = "gitdir:${config.home.homeDirectory}/generic/vault/";
        contents.core.hooksPath = ".githooks";
      }
    ];
  };

  programs.delta = {
    enable = true;
    enableGitIntegration = true;
    # delta takes bat's theme from BAT_THEME, which the shell sets to the
    # current mode's, and its diff colors from the include above.
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
  # gh renders Markdown in the theme's glamour style, as ws's popups do.
  home.sessionVariables.GLAMOUR_STYLE = "${config.xdg.configHome}/theme/glamour.json";

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
