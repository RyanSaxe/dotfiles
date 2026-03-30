return {
  {
    "folke/which-key.nvim",
    opts = function(_, opts)
      opts.spec = opts.spec or {}

      table.insert(opts.spec, { "<leader>d", group = "diagnostics" })
      table.insert(opts.spec, { "<leader>dw", desc = "Workspace" })
      table.insert(opts.spec, { "<leader>db", desc = "Buffer" })
      table.insert(opts.spec, { "<leader>do", desc = "Open Files" })
    end,
  },

  {
    "folke/snacks.nvim",
    init = function()
      pcall(vim.keymap.del, "n", "<leader>d")
      pcall(vim.keymap.del, "n", "<leader>dw")
      pcall(vim.keymap.del, "n", "<leader>db")
      pcall(vim.keymap.del, "n", "<leader>do")
      pcall(vim.keymap.del, "n", "<leader>dp")
    end,
    keys = {
      {
        "<leader>dw",
        function()
          require("custom.lsp.pickers").workspace()
        end,
        desc = "Workspace",
      },
      {
        "<leader>db",
        function()
          require("custom.lsp.pickers").buffer()
        end,
        desc = "Buffer",
      },
      {
        "<leader>do",
        function()
          require("custom.lsp.pickers").open_files()
        end,
        desc = "Open Files",
      },
    },
  },

  {
    "neovim/nvim-lspconfig",
    init = function()
      local group = vim.api.nvim_create_augroup("custom_lsp_diag_progress_state", { clear = true })
      vim.api.nvim_create_autocmd("LspProgress", {
        group = group,
        callback = function(ev)
          require("custom.lsp.pickers").on_progress(ev)
        end,
      })
    end,
  },
}
