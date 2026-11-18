{
  lib,
  buildGoModule,
  tmux,
}:
buildGoModule {
  pname = "ws";
  version = "0.1.0";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.fileFilter (
      f: f.hasExt "go" || f.hasExt "lua" || f.name == "go.mod" || f.name == "go.sum"
    ) ./.;
  };

  vendorHash = "sha256-5/xeGFMbd/eXbcXqUoW8crgnL1BeDd9Vb+Yd3SWt3PE=";

  # TestATmuxSnapshot starts a tmux server of its own, and skips without tmux.
  nativeCheckInputs = [ tmux ];
  # -v names each test as it passes or skips, so a build log shows the
  # tmux test ran.
  checkFlags = [ "-v" ];

  # The Go module is called workspace; the command is ws.
  postInstall = "mv $out/bin/workspace $out/bin/ws";

  meta = {
    description = "Sessions, worktrees and popups for Rex and tmux";
    mainProgram = "ws";
  };
}
