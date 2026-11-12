# pair from its develop branch, pinned by flake.lock. pair has no
# dependencies and no build step, so the package is its shipped folders
# and node.
{
  stdenvNoCC,
  makeWrapper,
  nodejs_26,
  src,
}:
stdenvNoCC.mkDerivation {
  pname = "pair";
  version = "develop";
  inherit src;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    mkdir -p $out/lib/pair $out/bin
    cp -r package.json src guide adapters skills $out/lib/pair/
    makeWrapper ${nodejs_26}/bin/node $out/bin/pair --add-flags $out/lib/pair/src/cli.mjs
  '';

  meta.mainProgram = "pair";
}
