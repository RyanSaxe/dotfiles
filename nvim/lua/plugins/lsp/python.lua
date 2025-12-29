return {
  "neovim/nvim-lspconfig",
  opts = {
    servers = {
      -- disabling lsps that can be on machine other than ty and ruff
      zuban = false,
      pyright = false,
      basedpyright = {
        settings = {
          basedpyright = {
            disableOrganizeImports = true, -- Defer to Ruff
            analysis = {
              inlayHints = {
                variableTypes = true,
                functionReturnTypes = true,
                genericTypes = true,
              },
              diagnosticMode = "openFilesOnly", -- Critical for performance
              exclude = { ".venv", "venv" },
              autoSearchPaths = true,
              useLibraryCodeForTypes = true, -- Improves type inference by analyzing library source
              typeCheckingMode = "standard",
            },
          },
        },
      },
      pyrefly = false,
      pylsp = false,
      -- enabling ty and ruff with custom settings
      ty = {
        enabled = false,
        settings = {
          ty = {
            diagnosticMode = "workspace",
            inlayHints = {
              variableTypes = true,
              callArgumentNames = true,
            },
          },
        },
      },
      ruff = {
        init_options = {
          settings = {
            showSyntaxErrors = true,
            lineLength = 120,
            organizeImports = true,
          },
        },
      },
    },
  },
}
