-- Explorer bake-off: snacks explorer keeps LazyVim's <leader>e; fyler
-- gets <leader>E so both run side by side until one wins. mini.files
-- stays the quick edit-the-filesystem buffer meanwhile.
return {
  {
    "FylerOrg/fyler.nvim",
    dependencies = { "nvim-mini/mini.icons" },
    branch = "stable",
    opts = {},
    keys = {
      {
        "<leader>E",
        function()
          require("fyler").toggle({ kind = "split_right_most" })
        end,
        desc = "Fyler Explorer (right split)",
      },
    },
  },

  {
    "nvim-mini/mini.files",
    opts = {
      windows = {
        preview = true,
        width_focus = 30,
        width_preview = 100,
      },
      options = {
        use_as_default_explorer = true,
        -- Trash, never permanent delete.
        permanent_delete = false,
      },
      mappings = {
        go_in_plus = "<CR>",
        synchronize = "'",
      },
    },
  },
}
