# tmux's colors, as the @variables its styles use. `theme` has every
# running server re-read them.
{
  lib,
  t,
  c,
  wash,
  ...
}:
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
    # Neovim's Search and CurSearch: every match, and the one the cursor
    # is on.
    search = wash 0.3 c.sky;
    search_current = c.red;
  };
in
{
  "tmux-colors.conf" = lib.concatLines (
    lib.mapAttrsToList (name: color: ''set -g @${name} "${color}"'') colors
  );
}
