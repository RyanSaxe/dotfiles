# The terminal's own colors, in Rex's and Ghostty's formats, so both
# terminals show the same ones. The rex module stores Rex's two themes in
# its settings, and the ghostty module writes Ghostty's.
{
  lib,
  t,
  c,
  mode,
  wash,
  ...
}:
let
  both = dark: light: if mode == "dark" then dark else light;
  channels =
    color:
    map (i: lib.fromHexString (builtins.substring i 2 color)) [
      1
      3
      5
    ];
  byte = n: lib.toLower (lib.fixedWidthString 2 "0" (lib.toHexString n));

  # Catppuccin's terminal colors. Light mode swaps the grays, so black stays
  # the darker of each pair.
  gray =
    both
      {
        black = c.surface1;
        white = c.subtext0;
        brightBlack = c.surface2;
        brightWhite = c.subtext1;
      }
      {
        black = c.subtext1;
        white = c.surface2;
        brightBlack = c.subtext0;
        brightWhite = c.surface1;
      };
  hues = [
    c.red
    c.green
    c.yellow
    c.blue
    c.pink
    c.teal
  ];
  colors = {
    ansi = [
      gray.black
    ]
    ++ hues
    ++ [
      gray.white
      gray.brightBlack
    ]
    ++ hues
    ++ [ gray.brightWhite ];
    background = t.background;
    foreground = t.text;
    cursor = c.rosewater;
    cursorText = both c.crust c.base;
    selectionBackground = wash 0.2 c.overlay2;
    selectionForeground = t.text;
  };

  # Rex keeps each color as sRGB fractions.
  rexColor = color: {
    red = lib.elemAt (channels color) 0 / 255.0;
    green = lib.elemAt (channels color) 1 / 255.0;
    blue = lib.elemAt (channels color) 2 / 255.0;
    alpha = 1;
    colorSpace = "srgb";
  };
  # Rex stores colors 16 to 255 too: xterm's color cube and gray ramp.
  cubeLevels = [
    0
    95
    135
    175
    215
    255
  ];
  xterm =
    i:
    let
      n = i - 16;
      level = j: lib.elemAt cubeLevels (lib.mod j 6);
      gray = 8 + 10 * (i - 232);
      rgb =
        if i < 232 then
          map level [
            (n / 36)
            (n / 6)
            n
          ]
        else
          [
            gray
            gray
            gray
          ];
    in
    "#" + lib.concatMapStrings byte rgb;
  # Rex identifies a theme by its id, which the rex module selects. The ids,
  # times and sources are from when Rex imported Ghostty's Catppuccin files.
  rex =
    both
      {
        id = "custom-47F1463D-62EA-4D1A-AE4A-F422BE174B36";
        name = "Catppuccin Mocha";
        createdAt = 815870476.248853;
      }
      {
        id = "custom-9EB6C009-5725-4ED3-AD39-81DB0F2B6E67";
        name = "Catppuccin Latte";
        createdAt = 815870476.199275;
      };
in
{
  "rex-theme.json" = builtins.toJSON (
    rex
    // {
      appearance = mode;
      source.ghosttyFile.fileName = rex.name;
      palette = lib.mapAttrs (_: rexColor) (removeAttrs colors [ "ansi" ]) // {
        ansi = map rexColor colors.ansi;
        paletteBase = lib.genAttrs (map toString (lib.range 16 255)) (i: rexColor (xterm (lib.toInt i)));
        paletteGenerate = false;
        paletteHarmonious = false;
        paletteOverrides = { };
      };
    }
  );

  "ghostty-theme" = lib.concatLines (
    lib.imap0 (i: color: "palette = ${toString i}=${color}") colors.ansi
    ++ [
      "background = ${colors.background}"
      "foreground = ${colors.foreground}"
      "cursor-color = ${colors.cursor}"
      "cursor-text = ${colors.cursorText}"
      "selection-background = ${colors.selectionBackground}"
      "selection-foreground = ${colors.selectionForeground}"
    ]
  );
}
