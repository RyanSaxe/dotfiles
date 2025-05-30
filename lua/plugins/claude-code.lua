-- enabling claude code as toggle able directly inside neovim.
-- I prefer this variant for general chatting to an AI with context.
return {
  "greggh/claude-code.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim", -- Required for git operations
  },
  config = function()
    require("claude-code").setup()
  end,
}
