-- A satellite handler for mini.diff: paints each hunk's position on
-- the scrollbar in the semantic ops colors, so the right edge shows
-- the file's change shape at a glance.
local M = {}

function M.setup()
  local ok, handlers = pcall(require, "satellite.handlers")
  if not ok then
    return
  end
  local c = require("theme.chrome").colors()
  vim.api.nvim_set_hl(0, "SatelliteDiffAdd", { fg = c.add })
  vim.api.nvim_set_hl(0, "SatelliteDiffChange", { fg = c.change })
  vim.api.nvim_set_hl(0, "SatelliteDiffDelete", { fg = c.delete })

  handlers.register({
    name = "minidiff",
    ns = vim.api.nvim_create_namespace("satellite.minidiff"),
    config = { enable = true, overlap = true, priority = 5 },
    enabled = function()
      return package.loaded["mini.diff"] ~= nil
    end,
    setup = function(_, update)
      vim.api.nvim_create_autocmd("User", {
        pattern = "MiniDiffUpdated",
        group = vim.api.nvim_create_augroup("satellite_minidiff", { clear = true }),
        callback = vim.schedule_wrap(update),
      })
    end,
    update = function(bufnr, winid)
      local diff_ok, diff = pcall(require, "mini.diff")
      if not diff_ok then
        return {}
      end
      local data = diff.get_buf_data(bufnr)
      ---@type table[]
      local hunks = data and data.hunks or {}
      ---@type table[]
      local marks = {}
      ---@type table
      local util = require("satellite.util")
      for _, hunk in ipairs(hunks) do
        local group = hunk.type == "add" and "SatelliteDiffAdd"
          or hunk.type == "delete" and "SatelliteDiffDelete"
          or "SatelliteDiffChange"
        ---@type integer
        local pos = util.row_to_barpos(winid, math.max(0, (hunk.buf_start or 1) - 1))
        marks[#marks + 1] = { pos = pos, highlight = group, symbol = "│", unique = false }
      end
      return marks
    end,
  })
end

return M
