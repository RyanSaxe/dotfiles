-- Explorer bake-off: snacks explorer keeps LazyVim's <leader>e; fyler
-- gets <leader>E so both run side by side until one wins. mini.files
-- stays the quick edit-the-filesystem buffer meanwhile.
return {
  -- LazyVim binds <leader>E to the explorer's cwd variant and applies it
  -- after fyler's mapping; release it so fyler owns the key.
  {
    "folke/snacks.nvim",
    keys = { { "<leader>E", false } },
  },

  {
    "FylerOrg/fyler.nvim",
    dependencies = { "nvim-mini/mini.icons" },
    branch = "stable",
    opts = {
      extensions = {
        git = { enabled = true },
        -- Trash, never permanent delete (mirrors the mini.files stance).
        trash = { enabled = true },
        -- Keep the tree in sync with external filesystem changes.
        watcher = { enabled = true },
      },
      integrations = { icon = "mini_icons" },
      kind_presets = {
        split_right_most = {
          width = "30%",
          win_opts = {
            number = false,
            relativenumber = false,
            signcolumn = "no",
            cursorline = true,
          },
        },
      },
    },
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
