return {
  {
    "nvim-mini/mini.diff",
    event = "VeryLazy",
    dependencies = { "folke/snacks.nvim" },
    keys = {
      {
        "<leader>gdo",
        function()
          ---@param ref string
          require("git_diff_surfaces").pick_branch("Mini Diff: Select branch", function(ref)
            require("git_diff_surfaces").open_overlay(ref)
          end)
        end,
        desc = "Overlay diff (branch)",
      },
      {
        "<leader>gdO",
        function()
          ---@param ref string
          require("git_diff_surfaces").pick_commit("Mini Diff: Select commit", true, function(ref)
            require("git_diff_surfaces").open_overlay(ref)
          end)
        end,
        desc = "Overlay diff (commit)",
      },
      {
        "<leader>gdq",
        function()
          local diff_surfaces = require("git_diff_surfaces")
          if diff_surfaces.close_overlay() then
            return
          end

          local ok, lifecycle = pcall(require, "codediff.ui.lifecycle")
          if ok and lifecycle.get_session(vim.api.nvim_get_current_tabpage()) then
            lifecycle.close(vim.api.nvim_get_current_tabpage())
          end
        end,
        desc = "Close diff view",
      },
    },
  },
}
