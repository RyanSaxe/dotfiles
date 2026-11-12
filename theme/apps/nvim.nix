# Neovim's tokens, which its theme code under lua/theme reads: Catppuccin's
# colors, the roles its highlight groups use, and the code tiers.
{
  lib,
  t,
  c,
  mode,
  ...
}:
{
  "nvim-tokens.lua" = "return ${
    lib.generators.toLua { } {
      inherit mode;
      inherit (t) accent code;
      notify = t.second;
      roles = {
        bg = t.background;
        bg_alt = t.panel;
        bg_highlight = t.raised;
        fg = t.text;
        fg_muted = t.muted;
        fg_faint = t.faint;
        ghost = t.faint;
        border = t.border;
        warn = t.warn;
        success = t.ok;
        info = t.info;
      };
      palette = c // {
        inherit (t) chrome;
        semantic_add = t.added;
        semantic_delete = t.removed;
        semantic_change = t.changed;
      };
    }
  }\n";
}
