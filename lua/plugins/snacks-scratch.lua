-- TODO: make a snacks picker that shows these as preview files
return {
  {
    "folke/snacks.nvim",
    keys = {
      { "<leader>.", false },
      {
        "<leader>.t",
        function()
          Snacks.scratch.open({
            name = "TODO", -- this name makes it such that checkmate.nvim runs on this.
            ft = "markdown",
          })
        end,
        desc = "TODO List",
      },
      {
        "<leader>.m",
        function()
          Snacks.scratch.open({
            ft = "markdown",
          })
        end,
        desc = "Markdown",
      },
      {
        "<leader>.p",
        function()
          Snacks.scratch.open({
            ft = "python",
          })
        end,
        desc = "Python",
      },
      {
        "<leader>..",
        function()
          Snacks.scratch.open()
        end,
        desc = "Current File Type",
      },
    },
  },
}
