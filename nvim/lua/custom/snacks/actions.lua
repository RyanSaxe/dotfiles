-- actions.lua  ── custom actions for Snacks picker
-- Contains custom actions that can be used in various pickers

local M = {}

-- Stores the original resolved layout for each picker instance
-- This allows us to restore the exact layout that was active when the picker opened
local picker_states = {}

-- Captures and stores the original resolved layout configuration
-- Called once per picker instance to save the initial layout state
---@param picker snacks.Picker
local function ensure_original_layout_stored(picker)
  if not picker_states[picker.id] then
    local original = picker.resolved_layout and vim.deepcopy(picker.resolved_layout) or nil

    picker_states[picker.id] = {
      original = original,
    }
  end
end

-- Switches layout while preserving state and eliminating flicker
---@param picker snacks.Picker
---@param layout_name string
local function set_layout_with_state_preservation(picker, layout_name)
  local old_lazyredraw = vim.o.lazyredraw

  -- Capture state before switch
  local fullscreen = picker.layout and picker.layout.opts.fullscreen or false
  local hidden = picker.layout and vim.deepcopy(picker.layout.opts.hidden) or {}

  -- Prevent flicker by disabling redraw during transition
  vim.o.lazyredraw = true

  -- Switch layout
  picker:set_layout(layout_name)

  -- Restore state
  picker.layout.opts.fullscreen = fullscreen
  picker.layout.opts.hidden = hidden
  if fullscreen or next(hidden) then
    picker.layout:update()
  end

  -- Re-enable redraw and force single redraw
  vim.o.lazyredraw = old_lazyredraw
  vim.cmd.redraw()
end

---@param picker snacks.Picker
function M.switch_to_vertical_layout(picker)
  ensure_original_layout_stored(picker)
  set_layout_with_state_preservation(picker, "custom_vertical")
end

---@param picker snacks.Picker
function M.switch_to_horizontal_layout(picker)
  ensure_original_layout_stored(picker)
  set_layout_with_state_preservation(picker, "custom_horizontal")
end

---@param picker snacks.Picker
function M.restore_original_layout(picker)
  ensure_original_layout_stored(picker)
  local state = picker_states[picker.id]
  set_layout_with_state_preservation(picker, state.original)
end

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