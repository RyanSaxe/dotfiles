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
  # Linux installs the agents from nixpkgs, as modules/home/agents.nix says.
  agentPath =
    if pkgs.stdenv.hostPlatform.isLinux then
      "${config.home.path}/bin"
    else
      "$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin";

  # uv installs these into ~/.local/bin, and each switch adds any that are
  # missing. nix-update upgrades them. A fresh byor also registers its own
  # skill and hooks, so a new computer needs nothing by hand.
  uvTools = [
    "prek"
    "byor"
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
        gopls
        lua-language-server
        markdownlint-cli
        nil
        nixfmt
        prettier
        rust-analyzer
        shfmt
        stylua
        tree-sitter

        go
        nodejs_26
        uv

        age
        sops

        # What snacks.nvim draws a note's pictures, diagrams and math with:
        # ImageMagick for every picture, in the build that reads PDFs, and
        # LaTeX with the packages its math template loads.
        imagemagickBig
        (texliveBasic.withPackages (
          tex: with tex; [
            amsfonts
            mathtools
            preview
            standalone
            varwidth
            xcolor
          ]
        ))
      ]
      ++ [ mermaid-cli ]
    )
    # Rex and sketchybar use JetBrains Mono's Nerd Fonts, and Ghostty the
    # JetBrains Mono built into it.
    ++ lib.optionals (has "gui") [ pkgs.nerd-fonts.jetbrains-mono ]
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
            has() { PATH="${agentPath}" command -v "$1" > /dev/null; }
            agents=skill
            has claude && agents="$agents,claude-code"
            has codex && agents="$agents,codex"
            run "$HOME/.local/bin/byor" install --agents "$agents" < /dev/null
          fi
        fi
      done
    ''
  );

  # byor's global rules, its command rules, its style package and the
  # scripts their checks run, linked from the checkout so a rule byor writes
  # lands in the repo.
  # byor owns the rest of ~/.config/byor.
  xdg.configFile = lib.mkIf (has "personal") (
    lib.genAttrs [ "byor/rules" "byor/commands" "byor/packages" "byor/scripts" ] (path: {
      source = config.lib.file.mkOutOfStoreSymlink "${config.dotfiles.repo}/config/${path}";
    })
  );

  home.sessionPath = [ "$HOME/.local/bin" ];
}
