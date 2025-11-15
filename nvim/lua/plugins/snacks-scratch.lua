return {
  {
    "folke/snacks.nvim",
    keys = {
      { "<leader>.", false },
      {
        "<leader>.",
        function()
          require("custom.snacks.scratch").new_scratch()
        end,
        desc = "Toggle Scratch Buffer",
      },
    },
  },
}
