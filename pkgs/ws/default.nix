{ lib, buildGoModule }:
buildGoModule {
  pname = "ws";
  version = "0.1.0";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.fileFilter (f: f.hasExt "go" || f.name == "go.mod" || f.name == "go.sum") ./.;
  };

  vendorHash = "sha256-5/xeGFMbd/eXbcXqUoW8crgnL1BeDd9Vb+Yd3SWt3PE=";

  # The Go module is called workspace; the command is ws.
  postInstall = "mv $out/bin/workspace $out/bin/ws";

  meta = {
    description = "Sessions, worktrees and popups for Rex and tmux";
    mainProgram = "ws";
  };
}
