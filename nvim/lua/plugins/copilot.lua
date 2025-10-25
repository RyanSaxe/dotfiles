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
