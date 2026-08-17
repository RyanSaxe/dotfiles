-- The dense grid: an honest-maximalist control room wrapping the
-- buffer. The winbar (top) carries buffer telemetry — path,
-- diagnostics, LSP clients, encoding, size. The statusline (bottom)
-- carries session telemetry — mode, sync arrows, diff counts, words,
-- position. Every fact has a fixed column; nothing appears twice
-- (identity stays with the tabs, branch included).
return {
  "nvim-lualine/lualine.nvim",
  event = "VeryLazy",
  init = function()
    vim.opt.cmdheight = 0
    vim.opt.laststatus = 3
    vim.o.showmode = false
  end,
  opts = function()
    local chrome = require("theme.chrome")
    local c = chrome.colors()
    chrome.track_git()

    ---@return string
    local function mode_color()
      ---@type string
      local m = vim.fn.mode():sub(1, 1)
      if m == "i" then
        return c.notify
      elseif m == "v" or m == "V" or m == "\22" or m == "s" then
        return c.mauve
      elseif m == "c" then
        return c.pink
      elseif m == "R" then
        return c.red
      elseif m == "t" then
        return c.green
      end
      return c.accent
    end

    ---@return {add: integer, change: integer, delete: integer}|nil
    local function diff_summary()
      local ok, diff = pcall(require, "mini.diff")
      if not ok then
        return nil
      end
      local data = diff.get_buf_data(0)
      return data and data.summary
    end

    ---@return string
    local function lsp_clients()
      ---@type string[]
      local names = {}
      for _, client in ipairs(vim.lsp.get_clients({ bufnr = 0 })) do
        names[#names + 1] = client.name
      end
      return table.concat(names, "·")
    end

    ---@return string
    local function file_size()
      local bytes = vim.fn.getfsize(vim.api.nvim_buf_get_name(0))
      if bytes <= 0 then
        return ""
      end
      if bytes < 1024 then
        return bytes .. "b"
      end
      return string.format("%.1fk", bytes / 1024)
    end

    local flat = { fg = c.text, bg = c.crust }
    local muted = { fg = c.muted, bg = c.crust }
    local section = { a = flat, b = flat, c = flat }
    local special_fts = { "snacks_dashboard", "snacks_picker_list", "snacks_picker_input" }

    return {
      options = {
        theme = {
          normal = section,
          insert = section,
          visual = section,
          replace = section,
          command = section,
          terminal = section,
          inactive = section,
        },
        globalstatus = true,
        icons_enabled = false,
        component_separators = { left = "", right = "" },
        section_separators = { left = "", right = "" },
        disabled_filetypes = { statusline = special_fts, winbar = special_fts },
      },

      -- Bottom row: session telemetry.
      sections = {
        lualine_a = {
          {
            "mode",
            fmt = function(s)
              return s:sub(1, 3)
            end,
            color = function()
              return { fg = mode_color(), bg = c.crust, gui = "bold" }
            end,
          },
          {
            function()
              local reg = vim.fn.reg_recording()
              return reg ~= "" and ("● " .. reg) or ""
            end,
            color = { fg = c.err, bg = c.crust, gui = "bold" },
          },
        },
        lualine_b = {
          {
            function()
              ---@type integer
              local n = vim.g.chrome_ahead or 0
              return n > 0 and ("↑" .. n) or ""
            end,
            color = { fg = c.add, bg = c.crust },
          },
          {
            function()
              ---@type integer
              local n = vim.g.chrome_behind or 0
              return n > 0 and ("↓" .. n) or ""
            end,
            color = { fg = c.delete, bg = c.crust },
          },
        },
        lualine_c = {
          {
            function()
              local s = diff_summary()
              return (s and (s.add or 0) > 0) and ("+" .. s.add) or ""
            end,
            color = { fg = c.add, bg = c.crust },
          },
          {
            function()
              local s = diff_summary()
              return (s and (s.change or 0) > 0) and ("~" .. s.change) or ""
            end,
            color = { fg = c.change, bg = c.crust },
          },
          {
            function()
              local s = diff_summary()
              return (s and (s.delete or 0) > 0) and ("−" .. s.delete) or ""
            end,
            color = { fg = c.delete, bg = c.crust },
          },
        },
        lualine_x = {
          {
            function()
              return vim.fn.wordcount().words .. "w"
            end,
            color = muted,
          },
        },
        lualine_y = {},
        lualine_z = {
          { "location", color = muted, padding = { left = 1, right = 0 } },
          { "progress", color = muted },
        },
      },
      inactive_sections = {},

      -- Top row: buffer telemetry.
      winbar = {
        lualine_a = {
          {
            "filename",
            path = 1,
            symbols = { modified = " ●", readonly = " -", unnamed = "" },
            color = function()
              return { fg = vim.bo.modified and c.warn or c.text, bg = c.crust }
            end,
          },
        },
        lualine_b = {
          {
            "diagnostics",
            symbols = { error = "● ", warn = "▲ ", info = "◆ ", hint = "· " },
            colored = true,
            color = { bg = c.crust },
          },
        },
        lualine_x = { { lsp_clients, color = muted } },
        lualine_y = {
          {
            function()
              return vim.bo.fileencoding
            end,
            color = muted,
          },
        },
        lualine_z = { { file_size, color = muted } },
      },
      inactive_winbar = {
        lualine_a = { { "filename", path = 1, color = muted } },
      },
    }
  end,
}
