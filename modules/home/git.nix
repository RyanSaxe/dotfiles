{ config, lib, ... }:
let
  cfg = config.dotfiles;
in
lib.mkIf (lib.elem "base" cfg.roles) {
  programs = {
    git = {
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
        # delta's colors for the current mode, which `theme` relinks.
        { path = "${config.xdg.configHome}/theme/delta-colors.gitconfig"; }
      ]
      # The vault's pre-commit hook runs its check, bin/check.py, before each commit.
      ++ lib.optional (cfg.vault != null) {
        condition = "gitdir:${cfg.vault.dir}/";
        contents.core.hooksPath = ".githooks";
      };
    };

    delta = {
      enable = true;
      enableGitIntegration = true;
      # delta takes bat's theme and its diff colors from the include above.
      options.navigate = true;
    };

    gh = {
      enable = true;
      gitCredentialHelper.enable = true;
      settings = {
        git_protocol = "https";
        aliases.co = "pr checkout";
      };
    };

    # Dotfiles.tmTheme for each mode, which bat and delta share. bat's config
    # names the current mode's, and `theme` relinks it, as it does delta's
    # include.
    bat = {
      enable = true;
      themes = lib.genAttrs [ "dotfiles-dark" "dotfiles-light" ] (name: {
        src = config.xdg.configFile."theme/${lib.removePrefix "dotfiles-" name}/Dotfiles.tmTheme".source;
      });
    };
  };

  # The switch clones the vault when its folder is missing, and neither git
  # nor ssh asks anything: ssh trusts a host it hasn't seen, as answering
  # yes would, and fails rather than ask for a passphrase. A failed clone,
  # as before GitHub has this computer's key, prints why and the switch goes
  # on. LogLevel=ERROR keeps ssh's note about a new host out of that reason.
  # /usr/bin/ssh is the ssh git uses in a shell, and Apple's reads the
  # UseKeychain line GitHub's guide adds to ~/.ssh/config, which Nix's
  # openssh refuses.
  home = {
    activation.cloneVault = lib.mkIf (cfg.vault != null) (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        vault=${lib.escapeShellArg cfg.vault.dir}
        if [[ ! -e $vault ]] && ! error=$(
          export GIT_TERMINAL_PROMPT=0
          export GIT_SSH_COMMAND="/usr/bin/ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o LogLevel=ERROR"
          run ${lib.getExe config.programs.git.package} clone --quiet ${lib.escapeShellArg cfg.vault.remote} "$vault" 2>&1
        ); then
          # ssh ends its lines with a carriage return.
          reason=$(head -n 1 <<< "$error" | tr -d '\r')
          warnEcho "The vault wasn't cloned into $vault: ''${reason%.}. Run the switch again once GitHub accepts this computer's ssh key."
        fi
      ''
    );

    # gh renders Markdown in the theme's glamour style, as ws's popups do.
    sessionVariables.GLAMOUR_STYLE = "${config.xdg.configHome}/theme/glamour.json";
  };

  xdg.configFile."bat/config".source =
    config.lib.file.mkOutOfStoreSymlink "${config.xdg.configHome}/theme/bat-config";
}
