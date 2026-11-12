# tmux's colors, as the @variables its styles use. `theme` has every
# running server re-read them.
{ lib, t, ... }:
let
  colors = {
    bg = t.background;
    bg_alt = t.panel;
    chrome = t.chrome;
    surface = t.raised;
    border = t.border;
    fg = t.text;
    dim = t.faint;
    accent = t.accent;
    notify = t.second;
    warn = t.warn;
    info = t.info;
  };
in
{
  "tmux-colors.conf" = lib.concatLines (
    lib.mapAttrsToList (name: color: ''set -g @${name} "${color}"'') colors
  );
}
