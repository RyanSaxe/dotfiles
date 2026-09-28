local diff_surfaces = require("git_diff_surfaces")

return {
  {
    "esmuellert/codediff.nvim",
    cmd = { "CodeDiff" },
    dependencies = { "MunifTanjim/nui.nvim", "folke/snacks.nvim" },
    keys = {
      { "<leader>gr", group = "Review" },
      {
        "<leader>grq",
        function()
          -- One key closes whichever diff surface is up: the mini.diff
          -- overlay if this buffer has one, else the codediff tab. Ported
          -- from v1's <leader>gdq; the group moved to gr in v2.
          if diff_surfaces.close_overlay() then
            return
          end
          local ok, lifecycle = pcall(require, "codediff.ui.lifecycle")
          if ok and lifecycle.get_session(vim.api.nvim_get_current_tabpage()) then
            vim.cmd.tabclose()
          end
        end,
        desc = "Close diff view",
      },
      {
        "<leader>grf",
        function()
          ---@param ref string
          diff_surfaces.pick_branch("CodeDiff: File against branch", function(ref)
            diff_surfaces.open_codediff({ "file", ref })
          end)
        end,
        desc = "CodeDiff file (branch)",
      },
      {
        "<leader>grF",
        function()
          ---@param ref string
          diff_surfaces.pick_commit("CodeDiff: File against commit", true, function(ref)
            diff_surfaces.open_codediff({ "file", ref })
          end)
        end,
        desc = "CodeDiff file (commit)",
      },
      {
        "<leader>gra",
        function()
          ---@param ref string
          diff_surfaces.pick_branch("CodeDiff: All files against branch", function(ref)
            diff_surfaces.open_codediff({ ref })
          end)
        end,
        desc = "CodeDiff all files (branch)",
      },
      {
        "<leader>grA",
        function()
          ---@param ref string
          diff_surfaces.pick_commit("CodeDiff: All files against commit", false, function(ref)
            diff_surfaces.open_codediff({ ref })
          end)
        end,
        desc = "CodeDiff all files (commit)",
      },
      {
        "<leader>grs",
        function()
          ---@param ref string
          diff_surfaces.pick_branch("CodeDiff: Review commit stack from branch", function(ref)
            diff_surfaces.open_history_from_branch(ref)
          end)
        end,
        desc = "CodeDiff stack review (branch)",
      },
      {
        "<leader>grS",
        function()
          diff_surfaces.pick_commit(
            "CodeDiff: Review commit stack from commit",
            false,
            diff_surfaces.open_history_from_commit
          )
        end,
        desc = "CodeDiff stack review (commit)",
      },
    },
    opts = {
      explorer = {
        position = "bottom",
        height = 10,
        view_mode = "list",
        focus_on_select = true,
        line_stats = {
          enabled = true,
        },
      },
      history = {
        position = "bottom",
        height = 10,
        view_mode = "list",
        initial_focus = "history",
      },
      diff = {
        layout = "side-by-side",
        original_position = "left",
        disable_inlay_hints = true,
        cycle_next_hunk = false,
        cycle_next_file = false,
        cycle_hunks_across_files = true,
        jump_to_first_change = true,
      },
      keymaps = {
        view = {
          quit = "q",
          toggle_explorer = "<leader>b",
          focus_explorer = "<leader>e",
          next_hunk = { "]h", "<Tab>" },
          prev_hunk = { "[h", "<S-Tab>" },
          next_file = "]f",
          prev_file = "[f",
          diff_get = "do",
          diff_put = "dp",
          open_in_prev_tab = "gf",
          close_on_open_in_prev_tab = false,
          toggle_stage = "-",
          hunk_textobject = "ih",
          show_help = "?",
          align_move = "gm",
          toggle_layout = "t",
          toggle_compact = "gc",
        },
        explorer = {
          select = "<CR>",
          hover = "K",
          refresh = "R",
          toggle_view_mode = "i",
          stage_all = "S",
          unstage_all = "U",
          restore = "X",
          toggle_changes = "gu",
          toggle_staged = "gs",
          fold_open = "zo",
          fold_open_recursive = "zO",
          fold_close = "zc",
          fold_close_recursive = "zC",
          fold_toggle = "za",
          fold_toggle_recursive = "zA",
          fold_open_all = "zR",
          fold_close_all = "zM",
        },
        history = {
          select = "<CR>",
          toggle_view_mode = "i",
          refresh = "R",
          fold_open = "zo",
          fold_open_recursive = "zO",
          fold_close = "zc",
          fold_close_recursive = "zC",
          fold_toggle = "za",
          fold_toggle_recursive = "zA",
          fold_open_all = "zR",
          fold_close_all = "zM",
        },
      },
    },
    ---@param opts table CodeDiff setup opts from this spec
    config = function(_, opts)
      require("codediff").setup(opts)
      require("codediff_review").setup()
    end,
  },
}
