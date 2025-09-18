-- actions.lua  ── custom actions for Snacks picker
-- Contains custom actions that can be used in various pickers

local M = {}

-- Save buffer action for buffer picker
-- Saves all selected buffers that have unsaved changes
---@param picker snacks.picker.Picker
function M.save_buffer(picker)
  local saved_count = 0
  local saved_files = {}

  for _, item in ipairs(picker:selected({ fallback = true })) do
    if item.buf and vim.bo[item.buf].modified then
      -- Use buf_call to ensure we're in the right context
      vim.api.nvim_buf_call(item.buf, function()
        local success, err = pcall(vim.cmd, "write")
        if success then
          saved_count = saved_count + 1
          local filename = item.file or "[No Name]"
          -- Get just the filename for cleaner notification
          local display_name = vim.fn.fnamemodify(filename, ":t")
          if display_name == "" then
            display_name = "[No Name]"
          end
          table.insert(saved_files, display_name)
        else
          vim.notify("Failed to save buffer " .. (item.file or "[No Name]") .. ": " .. err, vim.log.levels.ERROR)
        end
      end)
    end
  end

  -- Provide user feedback
  if saved_count > 0 then
    local message = saved_count == 1
      and "Saved: " .. saved_files[1]
      or "Saved " .. saved_count .. " buffers: " .. table.concat(saved_files, ", ")
    vim.notify(message, vim.log.levels.INFO)

    -- Refresh picker to update modified indicators
    picker:refresh()
  else
    vim.notify("No modified buffers to save", vim.log.levels.WARN)
  end
end

return M