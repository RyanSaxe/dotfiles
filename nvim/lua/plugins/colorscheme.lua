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
      -- local old_bg = c.bg
      -- c.bg = c.bg_dark
      -- c.bg_dark = old_bg
      c.bg_statusline = c.bg
      c.bg_float = c.bg
      -- c.bg_float = old_bg
    end,
    on_highlights = function(hl, c)
      -- Load pokemon colors from cache file (created by dashboard)
      -- This allows bufferline and other highlights to match the pokemon theme
      local pokemon_prominent = c.blue -- fallback to TokyoNight blue

      local env_file = vim.fn.expand("~/.cache/pokemon-colors.env")
      if vim.fn.filereadable(env_file) == 1 then
        -- Read and parse the env file
        local lines = vim.fn.readfile(env_file)
        for _, line in ipairs(lines) do
          local color = line:match('POKEMON_COLOR_PROMINENT="([^"]+)"')
          if color then
            pokemon_prominent = color
            break
          end
        end
      end

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
      -- private variables should be colored like global constants to make them stand out
      hl["@variable.private"] = { fg = c.red }
      -- make variables overall very clear and readable, with a blue theme
      hl["@variable.builtin"] = { fg = c.blue5 }
      hl["@variable"] = { fg = c.blue }
      hl["@variable.member"] = { fg = c.blue5 }
      hl["@variable.parameter"] = { fg = c.blue5 }
      -- in python make read only attributes (like properties) yellow
      -- hl["@lsp.mod.readonly.python"] = { fg = c.yellow }
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
      hl["@lsp.type.TypeParameter.python"] = { fg = c.teal }
      hl["@lsp.type.clsParameter.python"] = { fg = c.moon_pink }
      hl["@lsp.type.selfParameter.python"] = { fg = c.moon_pink }
      -- since this is virtual text, it looks annoying during a diff view.
      -- TODO: consider in common diff toggles also toggling inlay hints
      hl["LspInlayHint"] = { fg = c.dark3, bg = nil }
      hl["Comment"] = { fg = c.dark3 } -- comments and inlay hints in same format
      -- plugin specific changes
      hl["CursorLine"] = { bg = c.bg } -- if i want to not highlight the line my cursor is on
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
      hl["DiffAdd"] = { bg = Util.blend_bg("#00FF00", 0.1) }
      hl["DiffChange"] = { bg = Util.blend_bg("#0000FF", 0.1) } -- Util.blend_bg(c.git_purple, 0.5) }
      hl["DiffDelete"] = { bg = Util.blend_bg("#FF0000", 0.1) }
      hl["DiffAdded"] = { bg = Util.blend_bg("#00FF00", 0.1) }
      hl["DiffChanged"] = { bg = Util.blend_bg("#0000FF", 0.1) }
      hl["DiffDeleted"] = { bg = Util.blend_bg("#FF0000", 0.1) }
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
      hl["DiffText"] = { fg = c.red, bg = Util.blend_bg("#0000FF", 0.1) }
      -- diffview-specific diff highlights (override the plugin's defaults)
      -- NOTE: DiffText is overridden by window namespaces (red left, green right) in diffview.lua
      hl["DiffviewDiffAdd"] = { bg = Util.blend_bg("#00FF00", 0.1) }
      hl["DiffviewDiffChange"] = { bg = Util.blend_bg("#0000FF", 0.1) }
      hl["DiffviewDiffDelete"] = { bg = Util.blend_bg("#FF0000", 0.1) }
      hl["DiffviewDiffText"] = { fg = c.red, bg = Util.blend_bg("#0000FF", 0.1) }
      hl["SnacksDiffContext"] = { bg = c.bg }
      -- mini diff special highlighting for readable overlay
      hl["MiniDiffOverChange"] = { fg = c.red, bg = Util.blend_bg("#0000FF", 0.1) }
      hl["MiniDiffOverChangeBuf"] = { bg = Util.blend_bg("#00FF00", 0.1) }
      -- default dashboard colors (will be overridden by pokemon colors when dashboard opens)
      hl["SnacksDashboardTitle"] = { fg = Util.blend_bg(c.blue, 0.9) }
      hl["SnacksDashboardKey"] = { fg = "#FBE8B3" }
      hl["SnacksDashboardDesc"] = { fg = c.dark3 }
      -- make split borders more visible with brighter colors
      -- inactive splits use gray (matching tmux inactive pane borders)
      hl["WinSeparator"] = { fg = c.fg_gutter }
      hl["VertSplit"] = { fg = c.fg_gutter }
      -- ultra-minimal bufferline: just text with simple color coding
      -- IMPORTANT: all backgrounds MUST be c.bg for seamless integration
      hl["BufferLineFill"] = { bg = c.bg }
      -- match tabline background to normal background for seamless integration
      hl["TabLineFill"] = { bg = c.bg }

      -- offset backgrounds (for Neo-tree sidebar, etc) - also use normal background
      hl["BufferLineOffsetSeparator"] = { bg = c.bg }
      hl["BufferLineTruncMarker"] = { fg = c.dark3, bg = c.bg }

      hl["BufferLineBufferSelected"] = {
        fg = pokemon_prominent, -- Pokemon prominent color for active buffer
        bg = c.bg,
      }

      -- visible buffers (in other windows) - slightly dimmed white text
      hl["BufferLineBufferVisible"] = {
        fg = Util.blend_bg(c.fg, 0.8), -- slightly dimmed white (80% brightness)
        bg = c.bg,
      }

      -- inactive buffers (hidden) - gray text
      hl["BufferLineBuffer"] = {
        fg = c.dark3, -- dull gray
        bg = c.bg,
      }

      -- separators are invisible - same as background
      hl["BufferLineSeparatorSelected"] = { fg = c.bg, bg = c.bg }
      hl["BufferLineSeparatorVisible"] = { fg = c.bg, bg = c.bg }
      hl["BufferLineSeparator"] = { fg = c.bg, bg = c.bg }

      -- indicators also invisible
      hl["BufferLineIndicatorSelected"] = { fg = c.bg, bg = c.bg }
      hl["BufferLineIndicatorVisible"] = { fg = c.bg, bg = c.bg }
      hl["BufferLineIndicator"] = { fg = c.bg, bg = c.bg }

      -- modified/unsaved buffers - hierarchy: selected > visible > inactive
      hl["BufferLineModified"] = {
        fg = Util.blend_bg(c.orange, 0.3), -- very dull orange for inactive
        bg = c.bg,
      }
      hl["BufferLineModifiedSelected"] = {
        fg = c.orange, -- full orange when active
        bg = c.bg,
      }
      hl["BufferLineModifiedVisible"] = {
        fg = Util.blend_bg(c.orange, 0.6), -- medium dimmed orange for visible
        bg = c.bg,
      }

      -- close buttons - hierarchy: selected > visible > inactive
      hl["BufferLineCloseButton"] = {
        fg = Util.blend_bg(c.red, 0.3), -- very dull red for inactive
        bg = c.bg,
      }
      hl["BufferLineCloseButtonVisible"] = {
        fg = Util.blend_bg(c.red, 0.6), -- medium dimmed red for visible
        bg = c.bg,
      }
      hl["BufferLineCloseButtonSelected"] = {
        fg = c.red, -- full red for active
        bg = c.bg,
      }

      -- tabs - match exact buffer formatting
      hl["BufferLineTab"] = { fg = c.dark3, bg = c.bg } -- inactive = gray
      hl["BufferLineTabSelected"] = { fg = pokemon_prominent, bg = c.bg } -- active = pokemon prominent
      hl["BufferLineTabSeparator"] = { fg = c.bg, bg = c.bg } -- invisible separators
      hl["BufferLineTabSeparatorSelected"] = { fg = c.bg, bg = c.bg }
      hl["BufferLineTabClose"] = { fg = Util.blend_bg(c.red, 0.5), bg = c.bg } -- dim red X

      -- background elements - all should match editor background
      hl["BufferLineBackground"] = { fg = c.dark3, bg = c.bg } -- fallback gray text

      -- duplicate buffers (files with similar names) - match regular buffer colors
      hl["BufferLineDuplicate"] = { fg = c.dark3, bg = c.bg } -- hidden duplicates = gray
      hl["BufferLineDuplicateSelected"] = { fg = pokemon_prominent, bg = c.bg } -- active duplicate = pokemon prominent
      hl["BufferLineDuplicateVisible"] = { fg = Util.blend_bg(c.fg, 0.8), bg = c.bg } -- visible duplicate = slightly dimmed white

      -- group and pin backgrounds - also use normal background
      hl["BufferLineGroupLabel"] = { fg = c.dark3, bg = c.bg }
      hl["BufferLineGroupSeparator"] = { fg = c.bg, bg = c.bg }
      hl["BufferLinePick"] = { fg = c.red, bg = c.bg }
      hl["BufferLinePickSelected"] = { fg = c.red, bg = c.bg }
      hl["BufferLinePickVisible"] = { fg = c.red, bg = c.bg }

      -- ensure ALL text-bearing elements use our color scheme
      -- this is comprehensive to catch any edge cases
      hl["BufferLineTabSelected"] = { fg = pokemon_prominent, bg = c.bg }
      hl["BufferLineTab"] = { fg = c.dark3, bg = c.bg }
      hl["BufferLineNumbersSelected"] = { fg = pokemon_prominent, bg = c.bg }
      hl["BufferLineNumbersVisible"] = { fg = Util.blend_bg(c.fg, 0.8), bg = c.bg } -- slightly dimmed white
      hl["BufferLineNumbers"] = { fg = c.dark3, bg = c.bg }
    end,
  },
}
