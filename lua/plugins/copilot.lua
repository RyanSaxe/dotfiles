-- force copilot to use the current most up to date preview model
vim.g.copilot_settings = { selectedCompletionModel = "gpt-4o-copilot-2025-04-03" }

return {
  "zbirenbaum/copilot.lua",
  cmd = "Copilot",
  build = ":Copilot auth",
  event = "BufReadPost",
  opts = {
    suggestion = {
      enabled = true,
      auto_trigger = true,
      hide_during_completion = false,
      keymap = {
        accept = "<S-Tab>",
        next = "<Right>",
        prev = "<Left>",
      },
    },
    panel = { enabled = false },
    filetypes = {
      markdown = true,
      help = true,
      typr = false,
    },
  },
}
