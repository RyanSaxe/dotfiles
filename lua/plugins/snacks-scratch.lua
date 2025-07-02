local filetypes = {
  { text = "css" },
  { text = "go" },
  { text = "html" },
  { text = "javascript" },
  { text = "javascriptreact" },
  { text = "lua" },
  { text = "markdown" },
  { text = "python" },
  { text = "rust" },
  { text = "typescript" },
  { text = "typescriptreact" },
  { text = "zig" },
}
return {
  {
    "folke/snacks.nvim",
    keys = {
      -- { "<leader>.", false },
      {
        "-",
        function()
          require("custom.snacks.scratch").new_scratch(filetypes)
        end,
        desc = "Toggle Scratch Buffer",
      },
      {
        "_",
        function()
          require("custom.snacks.scratch").select_scratch()
        end,
        desc = "Select Scratch Buffer",
      },
      {
        "<leader>-",
        function()
          Snacks.scratch.open({
            name = "TODO", -- this name makes it such that checkmate.nvim runs on this.
            ft = "markdown",
          })
        end,
        desc = "Open TODO List",
      },
    },
  },
}
