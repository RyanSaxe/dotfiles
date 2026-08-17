-- Copilot owns ghost text; blink never draws its own and has no copilot
-- source. S-Tab accepts (wired in completion.lua). <leader>tc turns it
-- off globally when it is being noisy — copilot.lua already tracks that
-- state, so nothing here keeps a copy of it.
return {
  "zbirenbaum/copilot.lua",
  cmd = "Copilot",
  build = ":Copilot auth",
  event = "InsertEnter",
  keys = {
    {
      "<leader>tc",
      function()
        local command = require("copilot.command")
        local was_disabled = require("copilot.client").is_disabled()
        if was_disabled then
          command.enable()
        else
          command.disable()
        end
        vim.notify("Copilot " .. (was_disabled and "enabled" or "disabled"), vim.log.levels.INFO)
      end,
      desc = "Toggle Copilot",
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
    -- Commit messages are prose worth completing; copilot's own defaults
    -- decide the rest.
    filetypes = {
      gitcommit = true,
    },
    -- Real buffers only: never scratch, terminal, or plugin windows.
    ---@param bufnr integer
    ---@return boolean
    should_attach = function(bufnr)
      return vim.bo[bufnr].buflisted and vim.bo[bufnr].buftype == ""
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
