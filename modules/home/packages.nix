# Command-line tools, by role. A tool goes in the list of the role that
# needs it; programs with their own module (git, tmux, Neovim) install
# themselves there.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  has = role: lib.elem role config.dotfiles.roles;

  # uv installs these into ~/.local/bin, and each switch adds any that are
  # missing. nix-update upgrades them. A fresh byor also registers its own
  # skill and hooks, so a new computer needs nothing by hand.
  uvTools = [
    "prek"
    "byor"
    "pylatexenc"
  ];

  # mmdc draws with a browser, and nixpkgs has no Chromium for Macs, so on
  # a Mac it uses Google Chrome.
  mermaid-cli =
    if pkgs.stdenv.hostPlatform.isDarwin then
      pkgs.symlinkJoin {
        name = "mermaid-cli-with-chrome";
        paths = [ pkgs.mermaid-cli ];
        nativeBuildInputs = [ pkgs.makeWrapper ];
        postBuild = ''
          wrapProgram $out/bin/mmdc --set PUPPETEER_EXECUTABLE_PATH \
            "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
        '';
      }
    else
      pkgs.mermaid-cli;
in
{
  home.packages =
    lib.optionals (has "base") (
      with pkgs;
      [
        curl
        fd
        fzf
        jq
        ripgrep
        rsync
        tree
        wget

        # Neovim's language servers and formatters. Mason fills in the rest.
        ast-grep
        lua-language-server
        markdownlint-cli
        prettier
        shfmt
        stylua
        tree-sitter

        nodejs_26
        uv

        age
        sops
      ]
      ++ [ mermaid-cli ]
    )
    # Rex uses FiraCode Nerd Font and sketchybar JetBrainsMono Nerd Font.
    # Ghostty keeps its built-in font.
    ++ lib.optionals (has "gui") [
      pkgs.nerd-fonts.fira-code
      pkgs.nerd-fonts.jetbrains-mono
    ]
    ++ lib.optionals (has "personal") [
      pkgs.pi-coding-agent
      pkgs.pnpm
      (pkgs.python312.withPackages (
        python: with python; [
          numpy
          pillow
          websocket-client
        ]
      ))
    ];

  home.activation.uvTools = lib.mkIf (has "base") (
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      for tool in ${lib.escapeShellArgs uvTools}; do
        if ! ${pkgs.uv}/bin/uv tool list 2>/dev/null | grep -q "^$tool "; then
          run ${pkgs.uv}/bin/uv tool install "$tool"
          if [ "$tool" = byor ]; then
            # Only the agents this computer has, since Claude isn't allowed on
            # every one. The switch's own PATH has none of their folders.
            has() { PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin" command -v "$1" > /dev/null; }
            agents=skill
            has claude && agents="$agents,claude-code"
            has codex && agents="$agents,codex"
            run "$HOME/.local/bin/byor" install --agents "$agents" < /dev/null
          fi
        fi
      done
    ''
  );

  # byor's global rules, its style package and the scripts their checks
  # run, linked from the checkout so a rule byor writes lands in the repo.
  # byor owns the rest of ~/.config/byor.
  xdg.configFile = lib.mkIf (has "personal") (
    lib.genAttrs [ "byor/rules" "byor/packages" "byor/scripts" ] (path: {
      source = config.lib.file.mkOutOfStoreSymlink "${config.dotfiles.repo}/config/${path}";
    })
  );

  home.sessionPath = [ "$HOME/.local/bin" ];
}
