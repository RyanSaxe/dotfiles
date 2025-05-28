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
            lint = { enable = false }, -- linting comes from pyright. only use ruff for formatting.
          },
        },
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
              diagnosticMode = "openFilesOnly", --"workspace" may make the entire project slow.
              exclude = { ".venv", "venv" },
              autoImportCompletions = true,
              autoSearchPaths = true,
              disableOrganizeImports = true,
              -- parameters on how strict basedpyright should be
              -- strictGenericNarrowing = true, I like this, but it slows down based pyright
              typeCheckingMode = "basic",
            },
          },
        },
      },
    },
  },
}
