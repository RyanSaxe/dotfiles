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

      -- Use TokyoNight's natural darker background for floats
      -- bg_dark defaults to #16161e (slightly darker than main bg #1a1b26)
      c.bg_float = c.bg_dark
    end,
    on_highlights = function(hl, c)
      -- Load pokemon colors from cache file (created by dashboard)
      -- This allows bufferline and other highlights to match the pokemon theme
      local pokemon_prominent = c.blue -- fallback to TokyoNight blue
      local pokemon_bright = c.orange -- fallback to TokyoNight orange

      local env_file = vim.fn.expand("~/.cache/pokemon-colors.env")
      if vim.fn.filereadable(env_file) == 1 then
        -- Read and parse the env file
        local lines = vim.fn.readfile(env_file)
        for _, line in ipairs(lines) do
          local prominent = line:match('POKEMON_COLOR_PROMINENT="([^"]+)"')
          if prominent then
            pokemon_prominent = prominent
          end
          local bright = line:match('POKEMON_COLOR_BRIGHT="([^"]+)"')
          if bright then
            pokemon_bright = bright
          end
        end
      end

      -- Snacks Picker: Override cyan -> pokemon prominent, orange -> pokemon bright
      -- Orange highlights (input border, titles, accents)
      hl["SnacksPickerInputBorder"] = { fg = pokemon_bright, bg = c.bg_float }
      hl["SnacksPickerInputTitle"] = { fg = pokemon_bright, bg = c.bg_float }
      hl["SnacksPickerBoxTitle"] = { fg = pokemon_bright, bg = c.bg_float }
      hl["SnacksPickerPrompt"] = { fg = pokemon_bright }
      -- Cyan/blue highlights (main borders, titles, and prominent elements)
      hl["SnacksPickerBorder"] = { fg = pokemon_prominent, bg = c.bg_float }
      hl["SnacksPickerTitle"] = { fg = pokemon_prominent, bg = c.bg_float }
      hl["SnacksPickerToggle"] = { fg = pokemon_prominent, bg = Util.blend_bg(pokemon_prominent, 0.1) }
      hl["FloatBorder"] = { fg = pokemon_prominent, bg = c.bg_float }
      hl["FloatTitle"] = { fg = pokemon_prominent, bg = c.bg_float }

      -- docstrings should be slightly different color than comments but still faded to the background
      hl["@string.documentation"] = { fg = Util.blend_bg(c.purple, 0.5) }
      -- astral ty has a specific modifier with higher priority we need to hook into
      hl["@lsp.typemod.string.documentation.python"] = { fg = Util.blend_bg(c.purple, 0.5) }
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
      -- This is the no-context base state. custom.visual.treesitter_context_chrome
      -- dynamically tints these same surfaces when Treesitter Context is visible.
      local treesitter_context_bg = c.bg
      hl["CursorLine"] = { bg = Util.blend_bg(c.purple, 0.1) }
      hl["TreesitterContext"] = { bg = treesitter_context_bg }
      hl["TreesitterContextLineNumber"] = { fg = c.orange, bg = treesitter_context_bg } -- TODO: change to point to the cursor line number
      hl["TreesitterContextSeparator"] = { fg = c.purple }
      hl["TreesitterContextBottom"] = {
        bg = treesitter_context_bg,
        underline = true,
        sp = Util.blend_bg(c.purple, 0.5),
      }
      hl["TreesitterContextLineNumberBottom"] = {
        bg = treesitter_context_bg,
        underline = true,
        sp = Util.blend_bg(c.purple, 0.5),
      }
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
      -- DiffText highlights the specific changed text within a DiffChange line
      -- Using red foreground to make character-level changes stand out
      hl["DiffText"] = { fg = c.red, bg = Util.blend_bg("#0000FF", 0.1) }
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

      -- Statusline: darker background for UI chrome (even when lualine is disabled)
      hl["StatusLine"] = { fg = c.fg, bg = c.bg_dark }
      hl["StatusLineNC"] = { fg = c.dark3, bg = c.bg_dark } -- non-current windows

      -- Bufferline: Tab-style appearance with slanted separators
      -- Active tab uses normal bg (raised), inactive tabs use dark bg (recessed)
      hl["BufferLineFill"] = { bg = c.bg_dark }
      hl["TabLineFill"] = { bg = c.bg_dark }

      -- offset backgrounds (for Neo-tree sidebar, etc)
      hl["BufferLineOffsetSeparator"] = { bg = c.bg_dark }
      hl["BufferLineTruncMarker"] = { fg = c.dark3, bg = c.bg_dark }

      -- Active buffer: normal bg with pokemon prominent text (looks like raised tab)
      hl["BufferLineBufferSelected"] = {
        fg = pokemon_prominent,
        bg = treesitter_context_bg, -- match Treesitter Context band
      }

      -- visible buffers (in other windows) - slightly dimmed on dark bg
      hl["BufferLineBufferVisible"] = {
        fg = Util.blend_bg(c.fg, 0.8),
        bg = c.bg_dark,
      }

      -- inactive buffers (hidden) - gray text on dark bg
      hl["BufferLineBuffer"] = {
        fg = c.dark3,
        bg = c.bg_dark,
      }

      -- Slanted separators create tab appearance for active buffer
      -- Active: dark slant creates shadow/edge for raised tab effect
      hl["BufferLineSeparatorSelected"] = {
        fg = c.bg_dark, -- dark slant creates shadow/depth
        bg = treesitter_context_bg, -- active tab background
      }
      -- Inactive: invisible separators (same color as background)
      hl["BufferLineSeparatorVisible"] = { fg = c.bg_dark, bg = c.bg_dark }
      hl["BufferLineSeparator"] = { fg = c.bg_dark, bg = c.bg_dark }

      -- indicators match their respective backgrounds
      hl["BufferLineIndicatorSelected"] = { fg = treesitter_context_bg, bg = treesitter_context_bg }
      hl["BufferLineIndicatorVisible"] = { fg = c.bg_dark, bg = c.bg_dark }
      hl["BufferLineIndicator"] = { fg = c.bg_dark, bg = c.bg_dark }

      -- modified/unsaved buffers - hierarchy: selected > visible > inactive
      hl["BufferLineModified"] = {
        fg = Util.blend_bg(c.orange, 0.3), -- very dull orange for inactive
        bg = c.bg_dark,
      }
      hl["BufferLineModifiedSelected"] = {
        fg = c.orange, -- full orange when active
        bg = treesitter_context_bg,
      }
      hl["BufferLineModifiedVisible"] = {
        fg = Util.blend_bg(c.orange, 0.6), -- medium dimmed orange for visible
        bg = c.bg_dark,
      }

      -- close buttons - hierarchy: selected > visible > inactive
      hl["BufferLineCloseButton"] = {
        fg = Util.blend_bg(c.red, 0.3), -- very dull red for inactive
        bg = c.bg_dark,
      }
      hl["BufferLineCloseButtonVisible"] = {
        fg = Util.blend_bg(c.red, 0.6), -- medium dimmed red for visible
        bg = c.bg_dark,
      }
      hl["BufferLineCloseButtonSelected"] = {
        fg = c.red, -- full red for active
        bg = treesitter_context_bg,
      }

      -- tabs - match exact buffer formatting
      hl["BufferLineTab"] = { fg = c.dark3, bg = c.bg_dark } -- inactive = gray on dark bg
      hl["BufferLineTabSelected"] = { fg = pokemon_prominent, bg = treesitter_context_bg }
      hl["BufferLineTabSeparator"] = { fg = c.bg_dark, bg = c.bg_dark } -- invisible separators
      hl["BufferLineTabSeparatorSelected"] = { fg = treesitter_context_bg, bg = treesitter_context_bg }
      hl["BufferLineTabClose"] = { fg = Util.blend_bg(c.red, 0.5), bg = c.bg_dark } -- dim red X

      -- background elements - use darker background
      hl["BufferLineBackground"] = { fg = c.dark3, bg = c.bg_dark } -- fallback gray text

      -- duplicate buffers (files with similar names) - match regular buffer colors
      hl["BufferLineDuplicate"] = { fg = c.dark3, bg = c.bg_dark } -- hidden duplicates = gray
      hl["BufferLineDuplicateSelected"] = { fg = pokemon_prominent, bg = treesitter_context_bg }
      hl["BufferLineDuplicateVisible"] = { fg = Util.blend_bg(c.fg, 0.8), bg = c.bg_dark } -- visible duplicate = slightly dimmed white

      -- group and pin backgrounds - use darker background
      hl["BufferLineGroupLabel"] = { fg = c.dark3, bg = c.bg_dark }
      hl["BufferLineGroupSeparator"] = { fg = c.bg_dark, bg = c.bg_dark }
      hl["BufferLinePick"] = { fg = c.red, bg = c.bg_dark }
      hl["BufferLinePickSelected"] = { fg = c.red, bg = treesitter_context_bg }
      hl["BufferLinePickVisible"] = { fg = c.red, bg = c.bg_dark }

      -- ensure ALL text-bearing elements use our color scheme
      -- this is comprehensive to catch any edge cases
      hl["BufferLineTabSelected"] = { fg = pokemon_prominent, bg = treesitter_context_bg }
      hl["BufferLineTab"] = { fg = c.dark3, bg = c.bg_dark }
      hl["BufferLineNumbersSelected"] = { fg = pokemon_prominent, bg = treesitter_context_bg }
      hl["BufferLineNumbersVisible"] = { fg = Util.blend_bg(c.fg, 0.8), bg = c.bg_dark } -- slightly dimmed white
      hl["BufferLineNumbers"] = { fg = c.dark3, bg = c.bg_dark }

      -- Diagnostic indicators - ensure backgrounds match tab state
      -- Error diagnostics (red themed)
      hl["BufferLineError"] = { fg = Util.blend_bg(c.red, 0.3), bg = c.bg_dark }
      hl["BufferLineErrorVisible"] = { fg = Util.blend_bg(c.red, 0.6), bg = c.bg_dark }
      hl["BufferLineErrorSelected"] = { fg = c.red, bg = treesitter_context_bg }
      hl["BufferLineErrorDiagnostic"] = { fg = Util.blend_bg(c.red, 0.3), bg = c.bg_dark }
      hl["BufferLineErrorDiagnosticVisible"] = { fg = Util.blend_bg(c.red, 0.6), bg = c.bg_dark }
      hl["BufferLineErrorDiagnosticSelected"] = { fg = c.red, bg = treesitter_context_bg }

      -- Warning diagnostics (yellow themed)
      hl["BufferLineWarning"] = { fg = Util.blend_bg(c.yellow, 0.3), bg = c.bg_dark }
      hl["BufferLineWarningVisible"] = { fg = Util.blend_bg(c.yellow, 0.6), bg = c.bg_dark }
      hl["BufferLineWarningSelected"] = { fg = c.yellow, bg = treesitter_context_bg }
      hl["BufferLineWarningDiagnostic"] = { fg = Util.blend_bg(c.yellow, 0.3), bg = c.bg_dark }
      hl["BufferLineWarningDiagnosticVisible"] = { fg = Util.blend_bg(c.yellow, 0.6), bg = c.bg_dark }
      hl["BufferLineWarningDiagnosticSelected"] = { fg = c.yellow, bg = treesitter_context_bg }

      -- Info diagnostics (cyan themed)
      hl["BufferLineInfo"] = { fg = Util.blend_bg(c.cyan, 0.3), bg = c.bg_dark }
      hl["BufferLineInfoVisible"] = { fg = Util.blend_bg(c.cyan, 0.6), bg = c.bg_dark }
      hl["BufferLineInfoSelected"] = { fg = c.cyan, bg = treesitter_context_bg }
      hl["BufferLineInfoDiagnostic"] = { fg = Util.blend_bg(c.cyan, 0.3), bg = c.bg_dark }
      hl["BufferLineInfoDiagnosticVisible"] = { fg = Util.blend_bg(c.cyan, 0.6), bg = c.bg_dark }
      hl["BufferLineInfoDiagnosticSelected"] = { fg = c.cyan, bg = treesitter_context_bg }

      -- Hint diagnostics (cyan themed - prefer cyan over teal for hints)
      hl["DiagnosticHint"] = { fg = c.cyan }
      hl["DiagnosticSignHint"] = { fg = c.cyan }
      hl["DiagnosticVirtualTextHint"] = { fg = c.cyan }
      hl["DiagnosticUnderlineHint"] = { sp = c.cyan, undercurl = true }
      hl["DiagnosticFloatingHint"] = { fg = c.cyan }
      hl["BufferLineHint"] = { fg = Util.blend_bg(c.cyan, 0.3), bg = c.bg_dark }
      hl["BufferLineHintVisible"] = { fg = Util.blend_bg(c.cyan, 0.6), bg = c.bg_dark }
      hl["BufferLineHintSelected"] = { fg = c.cyan, bg = treesitter_context_bg }
      hl["BufferLineHintDiagnostic"] = { fg = Util.blend_bg(c.cyan, 0.3), bg = c.bg_dark }
      hl["BufferLineHintDiagnosticVisible"] = { fg = Util.blend_bg(c.cyan, 0.6), bg = c.bg_dark }
      hl["BufferLineHintDiagnosticSelected"] = { fg = c.cyan, bg = treesitter_context_bg }

      -- Generic diagnostic (fallback)
      hl["BufferLineDiagnostic"] = { fg = c.dark3, bg = c.bg_dark }
      hl["BufferLineDiagnosticVisible"] = { fg = Util.blend_bg(c.fg, 0.6), bg = c.bg_dark }
      hl["BufferLineDiagnosticSelected"] = { fg = c.fg, bg = treesitter_context_bg }

      -- GitHub Review Threads picker columns
      -- Used by custom/git/review_threads.lua picker
      hl["ReviewThreadsAuthor"] = { fg = c.purple }
      hl["ReviewThreadsCommentAuthor"] = { fg = c.blue }
      hl["ReviewThreadsKind"] = { fg = c.orange }
      hl["ReviewThreadsRepo"] = { fg = c.teal }
      hl["ReviewThreadsTime"] = { fg = c.moon_pink }
    end,
  },
}
