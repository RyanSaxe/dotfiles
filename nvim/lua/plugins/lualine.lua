return {
  "nvim-lualine/lualine.nvim",
  event = "VeryLazy",
  init = function()
    vim.opt.termguicolors = true
    vim.opt.cmdheight = 0
    vim.opt.laststatus = 2 -- per-window statuslines
    vim.o.showmode = false
    if vim.env.TMUX then
      vim.opt.guicursor = ""
    end
  end,
  opts = function()
    -- TokyoNight Night palette
    local C = {
      bg = "#1a1b26",
      fg = "#c0caf5",
      blue = "#7aa2f7",
      cyan = "#7dcfff",
      green = "#9ece6a",
      red = "#f7768e",
      yellow = "#e0af68",
      gray = "#565f89",
      gutter = "#3b4261",
      orange = "#ff9e64",
      purple = "#bb9af7",
    }
    local L, R = "", ""

    -- Ensure the fill behind sections matches our bg (kills the “black block”)
    vim.api.nvim_set_hl(0, "StatusLine", { bg = C.bg, fg = C.fg })
    vim.api.nvim_set_hl(0, "StatusLineNC", { bg = C.bg, fg = C.gray })

    -- Icons (fallbacks if LazyVim not present)
    local icons = (function()
      local ok, LV = pcall(require, "lazyvim.util")
      return ok and LV.config.icons
        or {
          diagnostics = { Error = " ", Warn = " ", Info = " ", Hint = " " },
          git = { added = " ", modified = " ", removed = " " },
        }
    end)()

    -- Mode color helper (for filename bg)
    local function mode_bg()
      local m = vim.fn.mode()
      if m:match("^[iI]") then
        return C.green
      elseif m:match("^[vV]") then
        return C.cyan
      elseif m:match("^R") then
        return C.red
      elseif m:match("^c") then
        return C.yellow
      else
        return C.blue
      end
    end

    -- File state → location bubble bg
    local function loc_bg()
      if vim.bo.readonly or not vim.bo.modifiable then
        return C.red
      end
      local name = vim.api.nvim_buf_get_name(0)
      if name == "" then
        return C.purple
      end
      if vim.bo.modified then
        return C.orange
      end
      return C.gray
    end

    -- Theme: only 'a' (mode) changes by mode; bar bg = C.bg
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
        a = { fg = C.bg, bg = C.cyan, gui = "bold" },
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

    -- ===== WINBAR =====
    -- Left: diagnostics (hide when zero). Right: git diff icons. Inactive: blank.
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
      -- no always_visible => hides when zero
      color = { fg = C.fg, bg = C.bg },
    }
    local winbar_gitdiff = {
      "diff",
      symbols = {
        added = icons.git.added or "+",
        modified = icons.git.modified or "~",
        removed = icons.git.removed or "-",
      },
      source = diff_source,
      color = { fg = C.fg, bg = C.bg },
    }

    -- Invisible caps to blend outer edges with bar bg (prevents stray blocks)
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

    -- ===== STATUSLINE BUBBLES =====
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
      padding = { left = 1, right = 1 },
    }

    -- Location first on the right; bg depends on file state (same active/inactive)
    local location_bubble = {
      "location",
      separator = { left = L, right = R },
      color = function()
        return { fg = C.bg, bg = loc_bg() }
      end,
      padding = { left = 1, right = 1 },
    }

    -- Filename next; bg follows current mode color.
    -- Active: bright text; Inactive: dimmed text.
    local function filename_color(active)
      local fg = active and C.bg or C.gutter -- dim when inactive
      return { fg = fg, bg = mode_bg() }
    end
    local filename_bubble_active = {
      "filename",
      path = 1,
      symbols = { modified = "", readonly = "", unnamed = "" }, -- no symbols
      separator = { left = L, right = R },
      color = function()
        return filename_color(true)
      end,
      padding = { left = 1, right = 1 },
    }
    local filename_bubble_inactive = vim.deepcopy(filename_bubble_active)
    filename_bubble_inactive.color = function()
      return filename_color(false)
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
        -- LEFT: cap → mode → branch
        lualine_a = { left_cap, mode_bubble },
        lualine_b = { branch_bubble },
        lualine_c = {},

        -- RIGHT: location → filename → cap
        lualine_x = {},
        lualine_y = { location_bubble, filename_bubble_active },
        lualine_z = { right_cap },
      },

      -- INACTIVE: left filename only (dimmed), right location (state color)
      inactive_sections = {
        lualine_a = { left_cap },
        lualine_b = { filename_bubble_inactive },
        lualine_c = {},
        lualine_x = {},
        lualine_y = { location_bubble },
        lualine_z = { right_cap },
      },

      -- WINBAR (active only): left diagnostics, right git; inactive blank
      winbar = { lualine_c = { winbar_diagnostics }, lualine_z = { winbar_gitdiff } },
      inactive_winbar = { lualine_c = {}, lualine_z = {} },

      extensions = { "neo-tree", "lazy", "fzf" },
    }
  end,
}
