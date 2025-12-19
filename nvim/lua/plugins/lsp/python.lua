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
