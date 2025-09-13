-- picker.lua  ── custom picker configurations and formatters
-- Contains custom picker sources, formatters, and configurations

local M = {}

-- Custom buffer formatter that enhances visual indicators for modified/readonly buffers
---@param item snacks.picker.Item
---@param picker snacks.picker.Picker
---@return snacks.picker.Highlight[]
function M.format_buffer(item, picker)
  local ret = {} ---@type snacks.picker.Highlight[]

  -- Buffer number (aligned to 3 characters)
  ret[#ret + 1] = { Snacks.picker.util.align(tostring(item.buf), 3), "SnacksPickerBufNr" }
  ret[#ret + 1] = { " " }

  -- Enhanced modified/readonly indicators with colored icons
  local flags = item.flags or ""
  if flags:match("+") then
    -- Modified buffer - use red/orange indicator
    ret[#ret + 1] = { "● ", "DiagnosticError" } -- Red dot for modified
  elseif flags:match("=") then
    -- Read-only buffer - use lock icon
    ret[#ret + 1] = { "󰌾 ", "Comment" } -- Lock icon for read-only, dimmed
  else
    -- Normal buffer - just spacing for alignment
    ret[#ret + 1] = { "  " }
  end

  -- Status flags (%, #, h, a) - remove the + and = since we show them as icons
  local status_flags = flags:gsub("[+=]", ""):gsub("^%s+", "")

  -- Enhanced highlighting for current/alternate buffer indicators
  if status_flags:match("%%") then
    -- Current buffer - make it stand out more
    ret[#ret + 1] = { Snacks.picker.util.align(status_flags, 2), "DiagnosticInfo" }
  elseif status_flags:match("#") then
    -- Alternate buffer - subtle but visible
    ret[#ret + 1] = { Snacks.picker.util.align(status_flags, 2), "@string.special" }
  else
    ret[#ret + 1] = { Snacks.picker.util.align(status_flags, 2), "SnacksPickerBufFlags" }
  end
  ret[#ret + 1] = { " " }

  -- Use the standard filename formatter for the file path
  vim.list_extend(ret, require("snacks.picker.format").filename(item, picker))

  return ret
end

-- Configuration for enhanced buffer picker
M.buffer_config = {
  finder = "buffers",
  format = M.format_buffer,
  hidden = false,
  unloaded = true,
  current = true,
  sort_lastused = true,
  win = {
    input = {
      keys = {
        -- Save buffer with Ctrl+S
        ["<c-s>"] = { require("custom.snacks.actions").save_buffer, mode = { "n", "i" } },
        -- Keep existing delete with Ctrl+X
        ["<c-x>"] = { "bufdelete", mode = { "n", "i" } },
      },
    },
    list = {
      keys = {
        -- Save buffer with Ctrl+S in list mode too
        ["<c-s>"] = require("custom.snacks.actions").save_buffer,
        -- Keep existing delete with dd
        ["dd"] = "bufdelete",
      },
    },
  },
}

return M