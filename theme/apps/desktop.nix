# The colors of one mode's desktop picture, which theme/desktop.py paints:
# a planet's curved horizon with the accent's light rising over it.
{ t, mode, ... }:
{
  "desktop.json" = builtins.toJSON {
    inherit mode;
    inherit (t)
      background
      chrome
      accent
      second
      info
      ;
  };
}
