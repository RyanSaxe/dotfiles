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
  catppuccin =
    lib.mapAttrs (_: color: color.hex)
      (lib.importJSON "${palette}/palette.json").${flavor}.colors;
  # Rex's sidebar color, which the bar and window frames share. It replaces
  # both of Catppuccin's recessed surfaces, so everything that paints one,
  # such as Neovim's floats and sidebars, paints this color.
  chrome = if mode == "dark" then "#1a1a27" else "#eaebee";
  c = catppuccin // {
    mantle = chrome;
    crust = chrome;
  };
  t = import ./meanings.nix { inherit c mode; };
  channels =
    color:
    map (i: lib.fromHexString (builtins.substring i 2 color)) [
      1
      3
      5
    ];
  byte = n: lib.toLower (lib.fixedWidthString 2 "0" (lib.toHexString n));
  # `amount` of a color over the background, as Neovim mixes its washes.
  # An added line's row is `wash 0.2 t.added`.
  wash =
    amount: color:
    "#"
    + lib.concatMapStrings byte (
      lib.zipListsWith (fg: bg: builtins.floor (fg * amount + bg * (1 - amount) + 0.5)) (channels color) (
        channels t.background
      )
    );
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
        wash
        ;
    }
  ) apps
)
