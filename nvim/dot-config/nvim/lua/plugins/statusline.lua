-- No statusline. The bottom row is code: window identity floats in
-- each window's top-right corner (incline), and the file's shape —
-- hunks, diagnostics, search hits, cursor — rides the right edge as a
-- decorated scrollbar (satellite). Buffer identity and branch stay on
-- the tab row.
return {
  { "nvim-lualine/lualine.nvim", enabled = false },

  {
    "b0o/incline.nvim",
    event = "VeryLazy",
    opts = function()
      local c = require("theme.chrome").colors()
      return {
        window = {
          margin = { vertical = 0, horizontal = 1 },
          padding = 1,
          zindex = 40,
          options = { winblend = 0 },
        },
        -- One window needs no floating identity: the tab row already
        -- names it. In splits the float is the only per-window label.
        hide = { cursorline = true, only_win = "count_ignored" },
        ---@param props { buf: integer, focused: boolean }
        render = function(props)
          local buf = props.buf
          local name = vim.api.nvim_buf_get_name(buf)
          if name == "" then
            return ""
          end
          ---@type table[]
          local parts = {}

          local reg = vim.fn.reg_recording()
          if reg ~= "" and props.focused then
            parts[#parts + 1] = { "● " .. reg .. " ", guifg = c.err, gui = "bold" }
          end

          ---@type integer[]
          local counts = { 0, 0 }
          for _, d in ipairs(vim.diagnostic.get(buf)) do
            if d.severity == vim.diagnostic.severity.ERROR then
              counts[1] = counts[1] + 1
            elseif d.severity == vim.diagnostic.severity.WARN then
              counts[2] = counts[2] + 1
            end
          end
          if counts[1] > 0 then
            parts[#parts + 1] = { "● " .. counts[1] .. " ", guifg = c.err }
          end
          if counts[2] > 0 then
            parts[#parts + 1] = { "▲ " .. counts[2] .. " ", guifg = c.warn }
          end

          parts[#parts + 1] = {
            vim.fn.fnamemodify(name, ":t"),
            guifg = vim.bo[buf].modified and c.warn or (props.focused and c.text or c.muted),
            gui = props.focused and "bold" or "None",
          }
          return parts
        end,
      }
    end,
  },

  {
    "lewis6991/satellite.nvim",
    event = "VeryLazy",
    config = function(_, opts)
      require("satellite").setup(opts)
      require("theme.satellite_diff").setup()
    end,
    opts = {
      current_only = true,
      winblend = 0,
      handlers = {
        cursor = { enable = true, symbols = { "⎺", "⎻", "⎼", "⎽" } },
        search = { enable = true },
        diagnostic = { enable = true, min_severity = vim.diagnostic.severity.WARN },
        gitsigns = { enable = false },
        marks = { enable = false },
        quickfix = { enable = true },
      },
    },
  },
}
