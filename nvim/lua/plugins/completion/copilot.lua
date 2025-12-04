-- Buffer-local Copilot state tracking
-- nil = use filetype default, true = force enabled, false = force disabled
local M = {}
M.buffer_state = {}
M.disabled_filetypes = {
  markdown = true,
  text = true,
  typr = true,
}

-- Get effective Copilot state for a buffer
function M.get_state(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local explicit = M.buffer_state[bufnr]
  if explicit ~= nil then
    return explicit
  end
  -- Use filetype default (enabled unless in disabled_filetypes)
  local ft = vim.bo[bufnr].filetype
  return not M.disabled_filetypes[ft]
end

-- Set Copilot state for a buffer and attach/detach accordingly
function M.set_state(bufnr, state)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  M.buffer_state[bufnr] = state
  if state then
    -- Force attach after enabling
    vim.schedule(function()
      local client = require("copilot.client")
      if not client.buf_is_attached(bufnr) then
        client.buf_attach(bufnr)
      end
    end)
  else
    require("copilot.client").buf_detach_if_attached(bufnr)
  end
end

-- Toggle Copilot for current buffer, returns new state
function M.toggle(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local new_state = not M.get_state(bufnr)
  M.set_state(bufnr, new_state)
  return new_state
end

-- Expose globally for toggle.lua to access
_G.CopilotBuffer = M

-- Clean up state when buffers are deleted (prevent memory leak)
vim.api.nvim_create_autocmd("BufDelete", {
  callback = function(args)
    M.buffer_state[args.buf] = nil
  end,
})

return {
  "zbirenbaum/copilot.lua",
  cmd = "Copilot",
  build = ":Copilot auth",
  event = "InsertEnter", -- Load on insert mode for better performance
  opts = {
    suggestion = {
      enabled = true,
      auto_trigger = true,
      debounce = 75, -- Wait 75ms after typing stops before requesting suggestions (reduces API calls)
      hide_during_completion = true, -- Hide Copilot suggestions when blink-cmp menu is open (prevents visual conflicts)
      keymap = {
        accept = false, -- Disabled (actual logic in blink-cmp.lua: Shift+Tab accepts, Tab accepts when blink menu is closed)
        next = "<Right>", -- Cycle to next Copilot suggestion
        prev = "<Left>", -- Cycle to previous Copilot suggestion
        dismiss = "<C-]>", -- Control-]: Fallback dismiss key
      },
    },
    panel = { enabled = false }, -- Panel is distracting, keep disabled
    filetypes = {
      gitcommit = true, -- Enable for git commit messages (disabled by default)
      -- Other disabled filetypes handled by M.disabled_filetypes + should_attach
    },
    -- Use buffer-local state tracking for attachment decisions
    -- This allows per-buffer toggling with session memory
    should_attach = function(bufnr)
      -- Standard checks (buflisted, buftype)
      if not vim.bo[bufnr].buflisted then
        return false
      end
      if vim.bo[bufnr].buftype ~= "" then
        return false
      end
      -- Use our buffer state tracking (respects per-buffer overrides)
      return M.get_state(bufnr)
    end,
  },
  -- Custom configuration to override C-c behavior with higher priority
  config = function(_, opts)
    require("copilot").setup(opts)

    -- Override C-c in insert mode: Universal cancel key that closes EVERYTHING
    -- Closes blink-cmp menu AND Copilot suggestion in one press
    vim.keymap.set("i", "<C-c>", function()
      local anything_closed = false

      -- Check and close blink-cmp menu if open
      local blink_ok, blink = pcall(require, "blink.cmp")
      if blink_ok and blink.is_visible() then
        blink.hide()
        anything_closed = true
      end

      -- Check and dismiss Copilot suggestion if visible
      if require("copilot.suggestion").is_visible() then
        require("copilot.suggestion").dismiss()
        anything_closed = true
      end

      -- If we closed anything, stay in insert mode
      if anything_closed then
        return ""
      end

      -- Otherwise, do default C-c behavior (exit insert mode)
      return vim.api.nvim_replace_termcodes("<C-c>", true, false, true)
    end, { expr = true, replace_keycodes = false, desc = "Cancel all (menu/Copilot) or exit insert mode" })
  end,
}
