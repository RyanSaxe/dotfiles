-- Python is ty + ruff, nothing else. The `false` entries are checkers
-- tried and rejected; naming them keeps a machine that happens to have
-- one installed from attaching it as a second opinion.
return {
  "neovim/nvim-lspconfig",
  opts = {
    servers = {
      basedpyright = false,
      pyright = false,
      pyrefly = false,
      pylsp = false,
      zuban = false,
      ty = {
        settings = {
          ty = {
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
            -- The one place line length is defined; projects override
            -- via their own pyproject/ruff config.
            lineLength = 120,
            organizeImports = true,
          },
        },
      },
    },
  },
}
