-- The instrument line: a fixed-geography statusline on the chrome
-- surface. Mode and recording sit left as solid chips; diagnostics,
-- the proportional diff gauge, and file position sit right. The gauge
-- and position are glyphs, not digits — indicators dim to surface
-- tones instead of disappearing, so the line never shifts.
local GAUGE_CELLS = 6
local BLOCKS = { "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█" }

return {
  "nvim-lualine/lualine.nvim",
  event = "VeryLazy",
  init = function()
    vim.opt.cmdheight = 0
    vim.opt.laststatus = 3
    vim.o.showmode = false
  end,
  opts = function()
    local c = require("theme.chrome").colors()

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

    -- Proportional cell counts for the gauge; nil while the buffer has
    -- no hunks (the dim track renders instead).
    ---@return {add: integer, change: integer, delete: integer}|nil
    local function gauge()
      local s = diff_summary()
      if not s then
        return nil
      end
      ---@type integer, integer, integer
      local add, change, delete = s.add or 0, s.change or 0, s.delete or 0
      local total = add + change + delete
      if total == 0 then
        return nil
      end
      -- Every nonzero series keeps at least one cell; the largest series
      -- absorbs the rounding remainder.
      ---@param n integer
      local function share(n)
        return n > 0 and math.max(1, math.floor(n / total * GAUGE_CELLS)) or 0
      end
      local cells = { add = share(add), change = share(change), delete = share(delete) }
      local used = cells.add + cells.change + cells.delete
      local largest = "add"
      if change > add then
        largest = "change"
      end
      if delete > math.max(add, change) then
        largest = "delete"
      end
      cells[largest] = cells[largest] + (GAUGE_CELLS - used)
      return cells
    end

    ---@param key "add"|"change"|"delete"
    ---@param color string
    local function gauge_segment(key, color)
      return {
        function()
          local cells = gauge()
          return cells and string.rep("▂", cells[key]) or ""
        end,
        color = { fg = color, bg = c.crust },
        padding = 0,
      }
    end

    local chrome = { fg = c.text, bg = c.crust }
    local muted = { fg = c.muted, bg = c.crust }
    local section = { a = chrome, b = chrome, c = chrome }

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
        disabled_filetypes = { statusline = { "snacks_dashboard" } },
      },
      sections = {
        lualine_a = {
          -- A crust cell ahead of the mode chip: the line's edge stays
          -- chrome-colored so ghostty's background extension shows frame,
          -- never mode color.
          {
            function()
              return " "
            end,
            color = chrome,
            padding = 0,
          },
          {
            "mode",
            fmt = function(s)
              return s:sub(1, 1)
            end,
            color = function()
              return { fg = c.crust, bg = mode_color(), gui = "bold" }
            end,
          },
          {
            function()
              local reg = vim.fn.reg_recording()
              return reg ~= "" and ("● " .. reg) or ""
            end,
            color = { fg = c.crust, bg = c.err, gui = "bold" },
          },
        },
        lualine_b = {},
        lualine_c = {},
        lualine_x = {
          {
            "diagnostics",
            symbols = { error = "● ", warn = "▲ ", info = "◆ ", hint = "· " },
            colored = true,
            color = { bg = c.crust },
          },
        },
        lualine_y = {
          gauge_segment("add", c.add),
          gauge_segment("change", c.change),
          gauge_segment("delete", c.delete),
          {
            function()
              return gauge() == nil and string.rep("▂", GAUGE_CELLS) or ""
            end,
            color = { fg = c.dim, bg = c.crust },
            padding = 0,
          },
        },
        lualine_z = {
          { "location", color = muted },
          {
            function()
              local line = vim.fn.line(".")
              local last = vim.fn.line("$")
              return BLOCKS[math.max(1, math.ceil(line / last * #BLOCKS))]
            end,
            color = function()
              return { fg = vim.bo.modified and c.warn or c.text, bg = c.crust }
            end,
            padding = { left = 0, right = 1 },
          },
        },
      },
      inactive_sections = {},
    }
  end,
}
