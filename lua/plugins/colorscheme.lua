local Util = require("tokyonight.util")
return {
  "folke/tokyonight.nvim",
  lazy = false,
  priority = 1000,
  opts = {
    style = "moon",
    on_colors = function(c)
      c.bright_red = "#ff0000"
      -- a less abrasive and more pastel magenta
      c.magenta2 = "#f76da7"
    end,
    on_highlights = function(hl, c)
      -- docstrings should be slightly different color than comments but still faded to the background
      hl["@string.documentation"] = { fg = Util.blend_bg(c.purple, 0.5) }
      -- I prefer when the literals are the same color and dont pop out at me
      local muted_literal = { fg = Util.blend_bg(c.blue1, 1.0) }
      hl["@string"] = muted_literal
      hl["@number"] = muted_literal
      hl["@number.float"] = muted_literal
      hl["@boolean"] = muted_literal
      hl["@function.builtin"] = muted_literal
      hl["@constant.builtin"] = "@type" -- muted_literal
      -- types and constants should clearly be readable
      hl["@type"] = { fg = c.teal }
      hl["@type.builtin"] = "@type"
      hl["@constant"] = { fg = c.red }
      -- functions should stand out
      hl["@function.method.call"] = "@function"
      hl["@function.call"] = "@function"
      hl["@function"] = { fg = c.blue6 }
      hl["@function.method"] = "@function"
      -- I like how the purple looks, and make it a base for all things that represent indented blocks
      hl["@keyword.conditional"] = { fg = c.purple }
      hl["@keyword.repeat"] = { fg = c.purple }
      hl["@keyword.exception"] = { fg = c.purple }
      hl["@keyword.function"] = { fg = c.purple }
      hl["@keyword.return"] = { fg = c.purple }
      hl["@keyword.type"] = { fg = c.purple }
      -- make things red and clear when the code is doing something that represents errors or issues
      hl["@keyword.risky"] = { fg = c.bright_red }
      hl["@keyword.error"] = { fg = c.red1 }
      -- make variables overall very clear and readable, with a blue theme
      hl["@variable.builtin"] = { fg = c.magenta2 }
      hl["@variable"] = { fg = c.blue1 }
      hl["@variable.member"] = { fg = c.magenta }
      hl["@variable.parameter"] = { fg = c.magenta2 }
      -- ensure punctuation and operations are clear and not distracting
      hl["@operator"] = { fg = c.purple }
      hl["@punctuation.delimiter"] = { fg = c.purple }
      hl["@punctuation.bracket"] = { fg = c.purple }
      hl["@punctuation.special"] = { fg = c.purple }
      -- Finally, just miscellaneous color shifts I prefer
      hl["@keyword.import"] = { fg = c.magenta }
      hl["@module"] = { fg = c.orange }
      hl["@constructor"] = "@function"
      -- lsp special handling
      hl["@lsp.type.namespace.python"] = "@module"
      hl["@lsp.type.decorator.python"] = "@function"
      hl["LspInlayHint"] = { fg = c.dark3 }
      -- I really dont like cursor highlighting the lines
      hl["CursorLine"] = { bg = c.bg }
    end,
  },
}
