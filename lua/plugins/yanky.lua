return {
  "gbprod/yanky.nvim",
  priority = 1000,
  lazy = false,
  keys = {
    {
      "<leader>y",
      function()
        if LazyVim.pick.picker.name == "telescope" then
          require("telescope").extensions.yank_history.yank_history({})
        else
          vim.cmd([[YankyRingHistory]])
        end
      end,
      mode = { "n", "x" },
      desc = "Open Yank History",
    },
    { "<leader>p", false },
  },
}
