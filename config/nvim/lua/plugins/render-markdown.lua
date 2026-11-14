-- LazyVim's markdown extra hands render-markdown a stripped configuration:
-- `checkbox.enabled = false`, no heading icons, no signs. These options merge
-- on top of that, and `checkbox` is the one that has to be spelled out --
-- render-markdown resolves `defaults <- preset <- user opts`, so LazyVim's
-- entry is a user opt and no preset can undo it. Without the override,
-- checkboxes render as literal `- [ ]`.
--
-- `render_modes = true` renders in every mode; the default `{'n','c','t'}`
-- un-renders the whole buffer the moment you enter insert. `check_icon` in
-- `anti_conceal.ignore` keeps the checkbox glyph on the cursor line so it does
-- not flicker back to `- [ ]` while moving through a list.
--
-- LaTeX is off because snacks draws math as pictures (plugins/images.lua),
-- and the two would both draw each equation.
--
-- A code block's closing fence shows as a thin edge rather than being hidden.
-- snacks draws a Mermaid diagram under that line, and a hidden line hides the
-- diagram with it (folke/snacks.nvim#2761).
return {
  "MeanderingProgrammer/render-markdown.nvim",
  ---@module 'render-markdown'
  ---@type render.md.UserConfig
  opts = {
    preset = "obsidian",
    render_modes = true,
    anti_conceal = { ignore = { check_icon = true } },
    checkbox = { enabled = true },
    bullet = { enabled = true },
    latex = { enabled = false },
    code = { border = "thin" },
    html = { enabled = true, comment = { conceal = true } },
  },
}
