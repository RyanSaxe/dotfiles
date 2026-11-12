# Every app's theme files for one mode, by file name. Each file in apps/
# turns the meanings into one app's format, so adding an app is adding a
# file there.
{
  lib,
  palette,
  mode,
}:
let
  flavor = if mode == "dark" then "mocha" else "latte";
  c = lib.mapAttrs (_: color: color.hex) (lib.importJSON "${palette}/palette.json").${flavor}.colors;
  t = import ./meanings.nix { inherit c mode; };
  apps = lib.attrNames (builtins.readDir ./apps);
in
lib.mergeAttrsList (
  map (
    app:
    import ./apps/${app} {
      inherit
        lib
        t
        c
        mode
        ;
    }
  ) apps
)
