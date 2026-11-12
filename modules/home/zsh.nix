# zsh and the prompt. The interactive config is config/zsh/zshrc, linked
# from the checkout so an edit applies in the next shell. This module
# supplies what it reads: the plugins, the environment and Starship.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles;
  inherit (pkgs.stdenv.hostPlatform) isDarwin;

  plugins = pkgs.linkFarm "zsh-plugins" {
    fzf-tab = "${pkgs.zsh-fzf-tab}/share/fzf-tab";
    zsh-autosuggestions = "${pkgs.zsh-autosuggestions}/share/zsh/plugins/zsh-autosuggestions";
    fast-syntax-highlighting = "${pkgs.zsh-fast-syntax-highlighting}/share/zsh/plugins/fast-syntax-highlighting";
  };
in
lib.mkIf (lib.elem "base" cfg.roles) {
  programs.zsh = {
    enable = true;
    shellAliases = {
      home-switch = "home-manager switch --flake '${cfg.repo}#${cfg.user}@${cfg.host}'";
      nix-update = "nix flake update --flake '${cfg.repo}' && ${lib.optionalString isDarwin "mac-switch && "}home-switch && uv tool upgrade --all";
    }
    // lib.optionalAttrs isDarwin {
      mac-switch = "sudo darwin-rebuild switch --flake '${cfg.repo}#${cfg.host}'";
    };
    # zshrc runs compinit itself, with a full check once a day.
    enableCompletion = false;
    history = {
      path = "$HOME/.zsh_history";
      size = 50000;
      save = 50000;
      share = true;
      ignoreAllDups = true;
      # A command typed with a leading space is kept like any other.
      ignoreSpace = false;
    };
    # The keychain is macOS's: on Linux the lookup would export an empty key.
    profileExtra = lib.mkIf (lib.elem "personal" cfg.roles && isDarwin) ''
      # Gaia's OpenRouter key, kept in the login keychain, for Gaia's engine.
      export OPENROUTER_API_KEY="$(security find-generic-password -s gaia-openrouter -a openrouter -w 2>/dev/null)"
    '';
    envExtra =
      lib.optionalString isDarwin ''
        # Homebrew only installs a few apps now, so its commands go last.
        [[ -d /opt/homebrew/bin ]] && path+=(/opt/homebrew/bin /opt/homebrew/sbin)
      ''
      + ''
        [[ -r ${config.sops.secrets.pair-hub-host.path} ]] && export PAIR_HUB_HOST=$(<${config.sops.secrets.pair-hub-host.path})
      '';
    initContent = ''
      ZSH_PLUGINS=${plugins}
      # fast-syntax-highlighting writes its compiled theme beside itself
      # by default, which is read-only in the Nix store.
      FAST_WORK_DIR=XDG:fsh
      source "$HOME/.config/zsh/zshrc"
    '';
  };

  home.sessionVariables = {
    LANG = "en_US.UTF-8";
    LC_ALL = "en_US.UTF-8";
    EDITOR = "nvim";
    VISUAL = "nvim";
    DOTFILES = cfg.repo;
    # The same uv paths for every launch, agents and Codex included.
    UV_CACHE_DIR = "$HOME/.cache/uv";
    UV_TOOL_BIN_DIR = "$HOME/.local/bin";
    UV_TOOL_DIR = "$HOME/.local/share/uv/tools";
    UV_PYTHON_INSTALL_DIR = "$HOME/.local/share/uv/python";
    UV_SYSTEM_CERTS = "true";
  };

  xdg.configFile."zsh".source = config.lib.file.mkOutOfStoreSymlink "${cfg.repo}/config/zsh";

  # zshrc runs prompt-segments.sh with dash, which macOS ships as /bin/dash.
  home.packages = [ pkgs.starship ] ++ lib.optional pkgs.stdenv.hostPlatform.isLinux pkgs.dash;
}
