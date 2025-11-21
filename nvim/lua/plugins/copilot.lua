return {
  "zbirenbaum/copilot.lua",
  cmd = "Copilot",
  build = ":Copilot auth",
  event = "InsertEnter", -- Load on insert mode for better performance (was BufReadPost)
  opts = {
    suggestion = {
      enabled = true,
      auto_trigger = true,
      debounce = 75, -- Wait 75ms after typing stops before requesting suggestions (reduces API calls)
      hide_during_completion = true, -- Hide Copilot suggestions when blink-cmp menu is open (prevents visual conflicts)
      keymap = {
        accept = "<Tab>", -- Tab accepts Copilot (actual logic in blink-cmp.lua smart Tab)
        next = "<Right>", -- Cycle to next Copilot suggestion
        prev = "<Left>", -- Cycle to previous Copilot suggestion
        dismiss = "<C-]>", -- Control-]: Fallback dismiss key
      },
    },
    panel = { enabled = false }, -- Panel is distracting, keep disabled
    filetypes = {
      markdown = false, -- Disabled for note-taking (obsidian.nvim)
      text = false, -- Disabled for plain text files
      help = true,
      gitcommit = true, -- Enable for git commit messages
      typr = false, -- Disable for typing practice game
    },
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
