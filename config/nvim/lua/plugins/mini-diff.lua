return {
  {
    "nvim-mini/mini.diff",
    event = "VeryLazy",
    dependencies = { "folke/snacks.nvim" },
    keys = {
      {
        "<leader>gro",
        function()
          ---@param ref string
          require("git_diff_surfaces").pick_branch("Mini Diff: Select branch", function(ref)
            require("git_diff_surfaces").open_overlay(ref)
          end)
        end,
        desc = "Overlay diff (branch)",
      },
      {
        "<leader>grO",
        function()
          ---@param ref string
          require("git_diff_surfaces").pick_commit("Mini Diff: Select commit", true, function(ref)
            require("git_diff_surfaces").open_overlay(ref)
          end)
        end,
        desc = "Overlay diff (commit)",
      },
    },
  },
}
