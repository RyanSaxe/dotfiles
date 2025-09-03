return {
  "nvim-lualine/lualine.nvim",
  event = "VeryLazy",
  init = function()
    vim.opt.termguicolors = true
    vim.opt.cmdheight = 0
    vim.opt.laststatus = 2
    vim.o.showmode = false
  end,
  opts = function()
    local C = {
      bg = "#1a1b26",
      fg = "#c0caf5",
      blue = "#7aa2f7",
      cyan = "#7dcfff",
      green = "#1abc9c",
      red = "#f7768e",
      yellow = "#e0af68",
      gray = "#565f89",
      gutter = "#3b4261",
      orange = "#ff9e64",
      purple = "#bb9af7",
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
        return C.yellow
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
        a = { fg = C.bg, bg = C.yellow, gui = "bold" },
        b = { fg = C.fg, bg = C.bg },
        c = { fg = C.fg, bg = C.bg },
      },
      inactive = { a = { fg = C.fg, bg = C.bg }, b = { fg = C.fg, bg = C.bg }, c = { fg = C.fg, bg = C.bg } },
    }

    -- WINBAR
    local winbar_navic = {
      function()
        local navic = require("nvim-navic")
        if not navic.is_available() then
          return ""
        end
        
        local location = navic.get_location()
        if location == "" then
          return ""
        end
        
        -- Custom truncation: keep first and last, truncate middle
        local parts = vim.split(location, " > ", { plain = true })
        if #parts <= 3 then
          return location -- no truncation needed
        end
        
        -- Keep first, show "..", keep last two
        return parts[1] .. " > .. > " .. parts[#parts - 1] .. " > " .. parts[#parts]
      end,
      cond = function()
        local navic = require("nvim-navic")
        return navic.is_available()
      end,
      color = { fg = C.fg, bg = C.bg },
    }
    
    -- diagnostics moved to winbar right side for easy spotting
    local winbar_diagnostics = {
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
    -- git diff moved to statusline with branch
    local statusline_gitdiff = {
      "diff",
      symbols = {
        added = icons.git.added or "+",
        modified = icons.git.modified or "~",
        removed = icons.git.removed or "-",
      },
      source = diff_source,
      separator = { left = L, right = R },
      color = { fg = C.bg, bg = C.gray },
      padding = { left = 1, right = 1 },
    }
    -- always-render filler so the winbar exists even if both sides are empty
    local winbar_filler = {
      function()
        return " "
      end,
      color = { fg = C.bg, bg = C.bg },
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

    local branch_bubble = {
      "branch",
      icon = "",
      separator = { left = L, right = R },
      color = { fg = C.bg, bg = C.gray },
      padding = {
        left = 1,
        right = 1,
      },
    }

    local location_bubble = {
      "location",
      separator = { left = L, right = R },
      color = function()
        return { fg = C.bg, bg = loc_bg() }
      end,
      padding = { left = 1, right = 1 },
    }

    -- FIX: stable width filename (no hidden status padding/markers)
    local filename_bubble_active = {
      "filename",
      path = 1, -- 3 for absolute
      file_status = false, -- <- prevents width changes on modified
      newfile_status = false,
      symbols = { modified = "", readonly = "", unnamed = "" }, -- explicit noop
      separator = { left = L, right = R },
      color = function()
        return { fg = C.bg, bg = mode_bg() }
      end,
      padding = { left = 1, right = 1 },
    }
    local filename_bubble_inactive = vim.deepcopy(filename_bubble_active)
    filename_bubble_inactive.color = function()
      return { fg = C.gutter, bg = mode_bg() }
    end

    return {
      options = {
        theme = theme,
        globalstatus = false,
        icons_enabled = false,
        component_separators = { left = "", right = "" },
        section_separators = { left = "", right = "" },
        refresh = { statusline = 120, winbar = 120, tabline = 300 },
        disabled_filetypes = {
          statusline = { "dashboard", "alpha", "ministarter", "snacks_dashboard" },
          winbar = { "dashboard", "alpha", "ministarter", "snacks_dashboard" },
        },
      },

      -- STATUSLINE
      sections = {
        -- left: cap → mode → branch → git diff
        lualine_a = { left_cap, mode_bubble },
        lualine_b = { branch_bubble, statusline_gitdiff },
        lualine_c = {},
        -- right: location → filename → cap
        lualine_x = {},
        lualine_y = { location_bubble, filename_bubble_active },
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

      -- WINBAR: left navic breadcrumbs, right diagnostics for easy spotting
      winbar = {
        lualine_a = { winbar_navic },
        lualine_x = { winbar_filler }, -- ensures bar exists even if both sides empty
        lualine_z = { winbar_diagnostics },
      },
      inactive_winbar = {
        lualine_c = { winbar_filler }, -- blank but present
        lualine_z = {},
      },

      extensions = { "neo-tree", "lazy", "fzf" },
    }
  end,
}
