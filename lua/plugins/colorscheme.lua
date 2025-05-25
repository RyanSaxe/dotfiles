local Util = require("tokyonight.util")
return {
  "folke/tokyonight.nvim",
  lazy = false,
  priority = 1000,
  opts = {
    style = "moon",
    on_colors = function(c)
      c.bg_highlight = c.bg_dark
    end,
    on_highlights = function(hl, c)
      -- docstrings should be slightly different color than comments but still faded to the background
      hl["@string.documentation"] = { fg = Util.blend_bg(c.purple, 0.5) }
      -- I prefer when the literals are the same color and dont pop out at me
      local muted_literal = { fg = c.blue1 }
      hl["@string"] = muted_literal
      hl["@number"] = muted_literal
      hl["@number.float"] = muted_literal
      hl["@boolean"] = muted_literal
      -- types and constants should clearly be readable
      hl["@type"] = { fg = c.teal }
      hl["@type.builtin"] = "@type"
      hl["@constant.builtin"] = "@type"
      hl["@constant"] = { fg = c.magenta2 }
      -- functions should stand out
      hl["@function.method.call"] = { fg = c.yellow }
      hl["@function.builtin"] = { fg = c.blue1 }
      hl["@function.call"] = { fg = c.yellow }
      hl["@function"] = { fg = c.magenta }
      hl["@function.method"] = "@function"
      -- I like how the purple looks, and make it a base for all things that represent indented blocks
      hl["@keyword.conditional"] = { fg = c.purple }
      hl["@keyword.repeat"] = { fg = c.purple }
      hl["@keyword.exception"] = { fg = c.purple }
      hl["@keyword.function"] = { fg = c.purple }
      hl["@keyword.return"] = { fg = c.purple }
      hl["@keyword.type"] = { fg = c.purple }
      -- make things red and clear when the code is doing something that represents errors or issues
      hl["@keyword.risky"] = { fg = c.bg, bg = c.magenta2 }
      hl["@keyword.error"] = { fg = c.red }
      -- make variables overall very clear and readable, with a blue theme
      hl["@variable.builtin"] = { fg = c.orange }
      hl["@variable"] = { fg = c.blue6 }
      hl["@variable.member"] = { fg = c.blue5 }
      hl["@variable.parameter"] = { fg = c.blue6 }
      -- ensure punctuation and operations are clear and not distracting
      hl["@operator"] = { fg = c.magenta }
      hl["@punctuation.delimiter"] = { fg = c.purple }
      hl["@punctuation.bracket"] = { fg = c.purple }
      hl["@punctuation.special"] = { fg = c.purple }
      -- Finally, just miscellaneous color shifts I prefer
      hl["@keyword.import"] = { fg = c.magenta }
      hl["@module"] = { fg = c.orange }
      hl["@constructor"] = { fg = c.yellow }
      -- terminal and cursor related changes
      hl["Cursor"] = { bg = c.magenta2, fg = c.magenta2 }
    end,
  },
}
