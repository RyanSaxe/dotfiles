return {
  "neovim/nvim-lspconfig",
  opts = {
    servers = {
      -- disable pyright to avoid duplication with basedpyright
      -- pyright = {
      --   settings = {
      --     pyright = {
      --       analysis = {
      --         ignore = { "*" },
      --         typeCheckingMode = false,
      --         disableOrganizeImports = true,
      --       },
      --     },
      --   },
      -- },
      -- -- disable diagnostics from ruff to avoid duplication with basedpyright
      ruff = {
        init_options = {
          settings = {
            showSyntaxErrors = false,
            lineLength = 120, -- set default line length to 120
            lint = {
              enable = false,
              -- select = { "COM819" }, -- only enable COM819 rule to remove trailing commas
            },
            format = {
              args = { "--line-length=120" }, -- ensure formatter also uses 120 character line length
            },
          },
        },
        -- Auto-fix COM819 (remove trailing commas) on save
        -- Note: formatting and import organization is handled by conform.nvim
        on_attach = function(client, bufnr)
          vim.api.nvim_create_autocmd("BufWritePre", {
            buffer = bufnr,
            callback = function()
              -- Run ruff's fixAll code action to apply COM819 fixes before formatting
              vim.lsp.buf.code_action({
                context = { only = { "source.fixAll" } },
                apply = true,
              })
            end,
          })
        end,
      },
      basedpyright = {
        settings = {
          basedpyright = {
            analysis = {
              inlayHints = {
                variableTypes = true,
                -- callArgumentNames = true,
                functionReturnTypes = true,
                genericTypes = true,
              },
              -- diagnosticMode = "workspace", -- use this one for smaller projects where it doesn't slow things down.
              diagnosticMode = "openFilesOnly", --bigger projects shouldn't run LSP always on the whole thing.
              exclude = { ".venv", "venv" },
              autoImportCompletions = true,
              autoSearchPaths = true,
              disableOrganizeImports = true,
              -- parameters on how strict basedpyright should be
              -- strictGenericNarrowing = true, I like this, but it slows down based pyright
              typeCheckingMode = "standard",
            },
          },
        },
      },
    },
  },
}
