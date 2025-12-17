return {
  "neovim/nvim-lspconfig",
  opts = {
    servers = {
      -- disabling lsps that can be on machine other than ty and ruff
      zuban = false,
      pyright = false,
      basedpyright = false,
      pyrefly = false,
      pylsp = false,
      -- enabling ty and ruff with custom settings
      ty = {
        init_options = {
          logLevel = "debug",
          logFile = vim.fn.stdpath("cache") .. "/ty.log",
        },
        settings = {
          ty = {
            diagnosticMode = "workspace",
            inlayHints = {
              variableTypes = false,
              callArgumentNames = false,
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
