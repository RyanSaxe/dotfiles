-- Copilot owns ghost text; blink never draws its own and has no copilot
-- source. S-Tab accepts (wired in completion.lua). Buffer-local state
-- lives here so toggles can flip copilot per buffer with session memory.

-- nil = filetype default, true = force enabled, false = force disabled
local M = {}
---@type table<integer, boolean>
M.buffer_state = {}
M.disabled_filetypes = {
  markdown = true,
  text = true,
}

---@param bufnr? integer
---@return boolean
function M.get_state(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local explicit = M.buffer_state[bufnr]
  if explicit ~= nil then
    return explicit
  end
  return not M.disabled_filetypes[vim.bo[bufnr].filetype]
end

---@param bufnr? integer
---@param state boolean|nil
function M.set_state(bufnr, state)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  M.buffer_state[bufnr] = state
  if state then
    vim.schedule(function()
      local client = require("copilot.client")
      if not client.buf_is_attached(bufnr) then
        -- Signature is buf_attach(force, bufnr); force is required so an
        -- explicit enable beats copilot's internal filetype gate
        -- (markdown is refused by default).
        client.buf_attach(true, bufnr)
      end
    end)
  else
    require("copilot.client").buf_detach_if_attached(bufnr)
  end
end

---@param bufnr? integer
---@return boolean
function M.toggle(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local new_state = not M.get_state(bufnr)
  M.set_state(bufnr, new_state)
  return new_state
end

-- Toggle keybinds reach this through the global.
_G.CopilotBuffer = M

vim.api.nvim_create_autocmd("BufDelete", {
  callback = function(args)
    M.buffer_state[args.buf] = nil
  end,
})

return {
  "zbirenbaum/copilot.lua",
  cmd = "Copilot",
  build = ":Copilot auth",
  event = "InsertEnter",
  keys = {
    {
      "<leader>tc",
      function()
        local enabled = _G.CopilotBuffer.toggle()
        vim.notify("Copilot " .. (enabled and "enabled" or "disabled") .. " for buffer", vim.log.levels.INFO)
      end,
      desc = "Toggle Copilot (Buffer)",
    },
  },
  opts = {
    suggestion = {
      enabled = true,
      auto_trigger = true,
      debounce = 75,
      -- No visual conflict: ghost text hides while the blink menu is open.
      hide_during_completion = true,
      keymap = {
        accept = false, -- S-Tab in completion.lua owns accept
        next = "<Right>",
        prev = "<Left>",
        dismiss = "<C-]>",
      },
    },
    panel = { enabled = false },
    filetypes = {
      gitcommit = true,
    },
    should_attach = function(bufnr)
      if not vim.bo[bufnr].buflisted then
        return false
      end
      if vim.bo[bufnr].buftype ~= "" then
        return false
      end
      return M.get_state(bufnr)
    end,
  },
  config = function(_, opts)
    require("copilot").setup(opts)

    -- C-c is the universal cancel: closes the blink menu AND the ghost
    -- text in one press, staying in insert mode; falls through to the
    -- stock C-c (exit insert) when there is nothing to close.
    vim.keymap.set("i", "<C-c>", function()
      local anything_closed = false

      local blink_ok, blink = pcall(require, "blink.cmp")
      if blink_ok and blink.is_visible() then
        blink.hide()
        anything_closed = true
      end

      if require("copilot.suggestion").is_visible() then
        require("copilot.suggestion").dismiss()
        anything_closed = true
      end

      if anything_closed then
        return ""
      end
      return vim.api.nvim_replace_termcodes("<C-c>", true, false, true)
    end, { expr = true, replace_keycodes = false, desc = "Cancel all (menu/copilot) or exit insert" })
  end,
}
