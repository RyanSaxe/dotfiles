return {
  "nvim-lualine/lualine.nvim",
  event = "VeryLazy",
  enabled = true,
  init = function()
    vim.opt.termguicolors = true
    vim.opt.cmdheight = 0
    vim.opt.laststatus = 2
    vim.o.showmode = false
  end,
  opts = function()
    -- Import tokyonight util for color blending and colors from colorscheme
    local Util = require("tokyonight.util")
    -- Get colors directly from tokyonight - will update automatically when theme changes
    local c = require("tokyonight.colors").setup()

    -- Load pokemon colors from cache file (created by dashboard)
    -- This allows lualine to match the pokemon theme automatically
    local pokemon_prominent = c.blue -- fallback to TokyoNight blue
    local pokemon_bright = c.orange -- fallback to TokyoNight orange

    local env_file = vim.fn.expand("~/.cache/pokemon-colors.env")
    if vim.fn.filereadable(env_file) == 1 then
      -- Read and parse the env file
      local lines = vim.fn.readfile(env_file)
      for _, line in ipairs(lines) do
        local color = line:match('POKEMON_COLOR_PROMINENT="([^"]+)"')
        if color then
          pokemon_prominent = color
        end
        color = line:match('POKEMON_COLOR_BRIGHT="([^"]+)"')
        if color then
          pokemon_bright = color
        end
      end
    end

    -- Create alias C for backwards compatibility with existing code
    local C = {
      bg = c.bg,
      fg = c.fg,
      blue = pokemon_prominent, -- Use pokemon prominent color for normal mode
      cyan = c.cyan,
      green = pokemon_bright, -- Use pokemon bright color for insert mode
      red = c.red,
      yellow = c.yellow,
      gray = c.comment,
      gutter = c.fg_gutter,
      orange = c.orange,
      purple = c.purple,
      pink = c.moon_pink or c.magenta2, -- use custom moon_pink if available
    }
    local L, R = "", ""

    -- ensure bar fill matches background (prevents edge artifacts)
    vim.api.nvim_set_hl(0, "StatusLine", { bg = C.bg, fg = C.fg })
    vim.api.nvim_set_hl(0, "StatusLineNC", { bg = C.bg, fg = C.gray })

    local icons = (function()
      local ok, LV = pcall(require, "lazyvim.util")
      return ok and LV.config.icons
        or {
          diagnostics = { Error = " ", Warn = " ", Info = " ", Hint = " " },
          git = { added = " ", modified = " ", removed = " " },
        }
    end)()

    local function mode_bg()
      local m = vim.fn.mode()
      if m:match("^[iI]") then
        return C.green
      elseif m:match("^[vV]") then
        return C.purple
      elseif m:match("^R") then
        return C.red
      elseif m:match("^c") then
        return C.pink
      else
        return C.blue
      end
    end

    local function loc_bg()
      if vim.bo.readonly or not vim.bo.modifiable then
        return C.red
      end
      if vim.api.nvim_buf_get_name(0) == "" then
        return C.purple
      end
      if vim.bo.modified then
        return C.yellow
      end
      return C.gray
    end

    local theme = {
      normal = {
        a = { fg = C.bg, bg = C.blue, gui = "bold" },
        b = { fg = C.fg, bg = C.bg },
        c = { fg = C.fg, bg = C.bg },
      },
      insert = {
        a = { fg = C.bg, bg = C.green, gui = "bold" },
        b = { fg = C.fg, bg = C.bg },
        c = { fg = C.fg, bg = C.bg },
      },
      visual = {
        a = { fg = C.bg, bg = C.purple, gui = "bold" },
        b = { fg = C.fg, bg = C.bg },
        c = { fg = C.fg, bg = C.bg },
      },
      replace = {
        a = { fg = C.bg, bg = C.red, gui = "bold" },
        b = { fg = C.fg, bg = C.bg },
        c = { fg = C.fg, bg = C.bg },
      },
      command = {
        a = { fg = C.bg, bg = C.pink, gui = "bold" },
        b = { fg = C.fg, bg = C.bg },
        c = { fg = C.fg, bg = C.bg },
      },
      inactive = { a = { fg = C.fg, bg = C.bg }, b = { fg = C.fg, bg = C.bg }, c = { fg = C.fg, bg = C.bg } },
    }

    -- WINBAR
    -- diagnostics component (flat styling)
    local statusline_diagnostics = {
      "diagnostics",
      symbols = {
        error = icons.diagnostics.Error or " ",
        warn = icons.diagnostics.Warn or " ",
        info = icons.diagnostics.Info or " ",
        hint = icons.diagnostics.Hint or " ",
      },
      colored = true,
      update_in_insert = false,
      color = { fg = C.fg, bg = C.bg },
    }
    local function diff_source()
      local ok, mini = pcall(require, "mini.diff")
      if not ok or not mini.get_buf_data then
        return nil
      end
      local d = mini.get_buf_data(0)
      local s = d and d.summary
      if s then
        return { added = s.add, modified = s.change, removed = s.delete }
      end
    end
    -- git diff component for winbar
    local winbar_gitdiff = {
      "diff",
      symbols = {
        added = icons.git.added or "+",
        modified = icons.git.modified or "~",
        removed = icons.git.removed or "-",
      },
      source = diff_source,
      cond = function()
        -- Hide winbar for buffergolf practice and reference buffers
        return not (vim.b.buffergolf_practice or vim.b.buffergolf_reference)
      end,
      color = { fg = C.fg, bg = C.bg },
    }
    -- always-render filler so the winbar exists even if both sides are empty
    local winbar_filler = {
      function()
        return " "
      end,
      cond = function()
        -- Hide winbar for buffergolf practice and reference buffers
        return not (vim.b.buffergolf_practice or vim.b.buffergolf_reference)
      end,
      color = { fg = C.bg, bg = C.bg },
    }

    -- filename component for inactive winbar - DISABLED (returns empty)
    local inactive_winbar_filename = {
      function()
        return "" -- Always return empty string to hide filename
      end,
      cond = function()
        return false -- Never show this component
      end,
      color = { fg = C.bg, bg = C.bg }, -- invisible just in case
    }

    -- NES (Next Edit Suggestions) indicator for winbar
    -- Shows copilot icon with hunk count in pokemon_bright color
    local winbar_nes = {
      function()
        local ok, Nes = pcall(require, "sidekick.nes")
        if not ok then
          return ""
        end

        -- Get edits for CURRENT buffer only
        local buf = vim.api.nvim_get_current_buf()
        local edits = Nes.get(buf)
        if #edits == 0 then
          return ""
        end

        -- Count total hunks for current buffer
        local total_hunks = 0
        for _, edit in ipairs(edits) do
          local diff = edit:diff()
          total_hunks = total_hunks + #diff.hunks
        end

        return string.format("%d  ", total_hunks) -- Copilot icon with hunk count
      end,
      cond = function()
        -- Hide for buffergolf buffers
        if vim.b.buffergolf_practice or vim.b.buffergolf_reference then
          return false
        end
        -- Only show when NES suggestions exist in current buffer
        local ok, Nes = pcall(require, "sidekick.nes")
        return ok and Nes.have()
      end,
      color = { fg = pokemon_bright, bg = C.bg }, -- Use pokemon_bright color
      padding = { left = 1, right = 1 },
    }

    -- invisible caps so outer edges match bg
    local left_cap = {
      function()
        return ""
      end,
      separator = { left = "", right = L },
      color = { fg = C.bg, bg = C.bg },
      padding = { left = 0, right = 0 },
    }
    local right_cap = {
      function()
        return ""
      end,
      separator = { left = R, right = "" },
      color = { fg = C.bg, bg = C.bg },
      padding = { left = 0, right = 0 },
    }

    -- STATUSLINE bubbles
    local mode_bubble = {
      "mode",
      fmt = function(s)
        return s:sub(1, 1)
      end,
      separator = { left = L, right = R },
      padding = { left = 1, right = 1 },
    }

    -- git branch component with mode-based colors
    local branch_bubble = {
      "branch",
      icon = "",
      separator = { left = L, right = R },
      color = function()
        return { fg = C.bg, bg = mode_bg() }
      end,
      padding = { left = 1, right = 1 },
    }

    local location_bubble = {
      "location",
      separator = { left = L, right = R },
      color = function()
        return { fg = C.bg, bg = loc_bg() }
      end,
      padding = { left = 1, right = 1 },
    }

    -- filename component with file status indication
    local filename_bubble_active = {
      "filename",
      path = 1, -- 3 for absolute
      file_status = false, -- <- prevents width changes on modified
      newfile_status = false,
      symbols = { modified = "", readonly = "", unnamed = "" }, -- explicit noop
      separator = { left = L, right = R },
      color = function()
        return { fg = C.bg, bg = loc_bg() }
      end,
      padding = { left = 1, right = 1 },
    }
    local filename_bubble_inactive = vim.deepcopy(filename_bubble_active)
    filename_bubble_inactive.color = function()
      return { fg = C.bg, bg = C.gray }
    end

    return {
      options = {
        theme = theme,
        globalstatus = true,
        icons_enabled = false,
        component_separators = { left = "", right = "" },
        section_separators = { left = "", right = "" },
        refresh = { statusline = 120, winbar = 120, tabline = 300 },
        disabled_filetypes = {
          statusline = {
            "dashboard",
            "alpha",
            "ministarter",
            "snacks_dashboard",
            "snacks_layout_box",
            "snacks_picker_input",
            "snacks_picker_list",
            "snacks_picker_preview",
            "Fyler",
            "BuffergolfStats",
          },
          winbar = {
            "dashboard",
            "alpha",
            "ministarter",
            "snacks_dashboard",
            "snacks_layout_box",
            "snacks_picker_input",
            "snacks_picker_list",
            "snacks_picker_preview",
            "Fyler",
            "BuffergolfStats",
          },
        },
      },

      -- STATUSLINE
      sections = {
        -- left: cap → mode → filename → diagnostics
        lualine_a = { left_cap, mode_bubble },
        lualine_b = { filename_bubble_active, statusline_diagnostics },
        lualine_c = {},
        -- right: location → git branch → cap
        lualine_x = {},
        lualine_y = { location_bubble, branch_bubble },
        lualine_z = { right_cap },
      },

      inactive_sections = {
        lualine_a = { left_cap },
        lualine_b = { filename_bubble_inactive },
        lualine_c = {},
        lualine_x = {},
        lualine_y = { location_bubble },
        lualine_z = { right_cap },
      },

      -- WINBAR: left NES indicator (pokemon_bright copilot icon + count), right git diff
      winbar = {
        lualine_a = { winbar_nes }, -- Shows copilot icon with hunk count when NES exists
        lualine_x = { winbar_filler }, -- ensures bar exists even if both sides empty
        lualine_z = { winbar_gitdiff },
      },
      inactive_winbar = {
        lualine_a = {},
        lualine_x = { winbar_filler }, -- ensures bar exists even when inactive
        lualine_z = { inactive_winbar_filename }, -- show filename in inactive splits (top right)
      },

      extensions = { "neo-tree", "lazy", "fzf" },
    }
  end,
}
