local Util = require("tokyonight.util")
return {
  "folke/tokyonight.nvim",
  lazy = false,
  priority = 100000000,
  opts = {
    style = "night",
    on_colors = function(c)
      -- original magenta2 is a bit aggressive
      c.old_magenta2 = c.magenta2
      c.bright_red = "#ff0000"
      -- a less abrasive and more pastel magenta
      c.magenta2 = "#f76da7"
      -- purple in the moon theme is this nice pink I like to reuse
      c.moon_pink = "#fca7ea"
      c.git_purple = "#ba55d3"
      -- experimentally trying an even darker background with lighter popups
      local old_bg = c.bg
      c.bg = c.bg_dark
      c.bg_dark = old_bg
      c.bg_float = old_bg
    end,
    on_highlights = function(hl, c)
      -- docstrings should be slightly different color than comments but still faded to the background
      hl["@string.documentation"] = { fg = Util.blend_bg(c.purple, 0.5) }
      -- I prefer when the literals are the same color and dont pop out at me
      local muted_literal = { fg = Util.blend_bg(c.fg, 0.7) }
      hl["@string"] = muted_literal
      hl["@number"] = muted_literal
      hl["@number.float"] = muted_literal
      hl["@boolean"] = muted_literal
      hl["@constant.builtin"] = muted_literal
      -- types and constants should clearly be readable
      hl["@type"] = { fg = c.teal }
      hl["@type.builtin"] = "@type"
      hl["@constant"] = { fg = c.red }
      -- functions should stand out
      hl["@function"] = { fg = c.orange }
      hl["@function.method.call"] = "@function"
      hl["@function.call"] = "@function"
      hl["@function.builtin"] = "@function" --{ fg = Util.blend_bg(c.orange, 0.5) }
      hl["@function.method"] = "@function"
      -- I like how the purple looks, and make it a base for all things that represent indented blocks
      hl["@keyword.conditional"] = { fg = c.purple }
      hl["@keyword.repeat"] = { fg = c.purple }
      hl["@keyword.exception"] = { fg = c.purple }
      hl["@keyword.function"] = { fg = c.purple }
      hl["@keyword.return"] = { fg = c.purple }
      hl["@keyword.type"] = { fg = c.purple }
      -- make things red and clear when the code is doing something that represents errors or issues
      -- for really risky ops we should never do, create queries for them in treesitter so we can
      -- represent them with formatting style that makes them stand out
      hl["@keyword.risky"] = { fg = c.old_magenta2, underline = true, bold = true, italic = true }
      hl["@keyword.error"] = { fg = c.old_magenta2 }
      -- make variables overall very clear and readable, with a blue theme
      hl["@variable.builtin"] = { fg = c.blue5 }
      hl["@variable"] = { fg = c.blue }
      hl["@variable.member"] = { fg = c.blue5 }
      hl["@variable.parameter"] = { fg = c.blue5 }
      -- ensure punctuation and operations are clear and not distracting
      hl["@operator"] = { fg = c.purple }
      hl["@punctuation.delimiter"] = { fg = c.purple }
      hl["@punctuation.bracket"] = { fg = c.purple }
      hl["@punctuation.special"] = { fg = c.purple }
      -- Finally, just miscellaneous color shifts I prefer
      hl["@keyword.import"] = { fg = c.purple }
      hl["@module"] = { fg = c.moon_pink }
      hl["@constructor"] = "@function"
      -- lsp special handling
      hl["@lsp.type.namespace.python"] = "@module"
      hl["@lsp.type.decorator.python"] = "@function"
      hl["@lsp.type.TypeParameter.python"] = { fg = c.blue }
      -- since this is virtual text, it looks annoying during a diff view.
      -- TODO: consider in common diff toggles also toggling inlay hints
      hl["LspInlayHint"] = { fg = c.dark3, bg = nil }
      hl["Comment"] = { fg = c.dark3 } -- comments and inlay hints in same format
      -- plugin specific changes
      hl["CursorLine"] = { bg = c.bg_dark } -- if i want to not highlight the line my cursor is on
      hl["TreesitterContext"] = { bg = c.bg }
      hl["TreesitterContextLineNumber"] = { fg = c.orange } -- TODO: change to point to the cursor line number
      hl["TreesitterContextSeparator"] = { fg = c.purple }
      -- make ghost text lightly pink so it's easier to see
      hl["BlinkCmpGhostText"] = { fg = Util.blend_bg(c.moon_pink, 0.5), bg = c.bg_dark }
      hl["LspGhostText"] = { fg = Util.blend_bg(c.moon_pink, 0.5), bg = c.bg_dark }
      hl["CopilotSuggestion"] = { fg = Util.blend_bg(c.moon_pink, 0.5) }
      -- -- overwriting the colors for todo comments
      hl["TodoBgPerf"] = { fg = Util.blend_bg(c.teal, 0.7), bold = true, italic = true }
      hl["TodoBgWarn"] = { fg = Util.blend_bg(c.yellow, 0.7), bold = true, italic = true }
      hl["TodoBgHack"] = { fg = Util.blend_bg(c.magenta2, 0.7), bold = true, italic = true }
      hl["TodoBgFix"] = { fg = Util.blend_bg(c.bright_red, 1.0), bold = true, italic = true }
      hl["TodoBgNote"] = { fg = Util.blend_bg(c.cyan, 0.7), bold = true, italic = true }
      hl["TodoBgTodo"] = { fg = Util.blend_bg(c.orange, 0.7), bold = true, italic = true }
      hl["TodoBgTest"] = { fg = Util.blend_bg(c.moon_pink, 0.7), bold = true, italic = true }
      hl["TodoFgPerf"] = "Comment" -- { fg = Util.blend_bg(c.moon_pink, 0.5) }
      hl["TodoFgWarn"] = "Comment" -- { fg = Util.blend_bg(c.yellow, 0.5) }
      hl["TodoFgHack"] = "Comment" -- { fg = Util.blend_bg(c.old_magenta2, 0.5) }
      hl["TodoFgFix"] = "Comment" -- { fg = Util.blend_bg(c.bright_red, 0.5) }
      hl["TodoFgNote"] = "Comment" -- { fg = Util.blend_bg(c.teal, 0.5) }
      hl["TodoFgTodo"] = "Comment" -- { fg = Util.blend_bg(c.cyan, 0.5) }
      hl["TodoFgTest"] = "Comment" -- { fg = Util.blend_bg(c.orange, 0.5) }
      -- git not properly reading overrides so specifying them here
      hl["DiffAdd"] = { bg = Util.blend_bg("#00FF00", 0.2) }
      hl["DiffChange"] = { bg = Util.blend_bg(c.git_purple, 0.5) }
      hl["DiffDelete"] = { bg = Util.blend_bg("#FF0000", 0.2) }
      hl["DiffAdded"] = { bg = Util.blend_bg("#00FF00", 0.3) }
      hl["DiffChanged"] = { bg = Util.blend_bg(c.git_purple, 0.5) }
      hl["DiffDeleted"] = { bg = Util.blend_bg("#FF0000", 0.2) }
      hl["MiniDiffSignAdd"] = { fg = Util.blend_bg(c.teal, 0.7) }
      hl["MiniDiffSignChange"] = { fg = Util.blend_bg(c.purple, 0.7) }
      hl["MiniDiffSignDelete"] = { fg = Util.blend_bg(c.red, 0.7) }
      hl["GitSignsAdd"] = { fg = Util.blend_bg(c.teal, 0.7) }
      hl["GitSignsChange"] = { fg = Util.blend_bg(c.purple, 0.7) }
      hl["GitSignsDelete"] = { fg = Util.blend_bg(c.red, 0.7) }
      -- diffview coloring in the file panel
      hl["DiffviewFilePanelInsertions"] = { fg = c.teal }
      hl["DiffviewFilePanelDeletions"] = { fg = c.red }
      -- diff text is always shown on a git change. I find the extra coloring distracting in diff view
      -- so we make the background identical to the change to avoid the double-highlighting effect
      -- in mini diff, however, we do apply different styling since we can properly apply them to base
      -- and the change. NOTE: possibly could implement something similar for diffview.
      hl["DiffText"] = { bg = Util.blend_bg(c.git_purple, 0.5) }
      -- mini diff special highlighting for readable overlay
      hl["MiniDiffOverChange"] = { fg = c.red, bg = Util.blend_bg(c.git_purple, 0.5) }
      hl["MiniDiffOverChangeBuf"] = { bg = Util.blend_bg("#00FF00", 0.2) }
      -- make sure code blocks are clearly readable via having a different background
      hl["RenderMarkdownCode"] = { bg = c.bg_highlight }
    end,
  },
}
