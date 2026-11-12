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
  # missing. nix-update upgrades them.
  uvTools = [
    "prek"
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

        uv

        age
        sops
      ]
      ++ [ mermaid-cli ]
    )
    ++ lib.optionals (has "personal") [
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
        fi
      done
    ''
  );

  home.sessionPath = [ "$HOME/.local/bin" ];
}
