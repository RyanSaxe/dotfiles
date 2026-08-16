-- Python is ty + ruff, nothing else. The explicit `false` entries stop
-- LazyVim or machine-present servers from attaching a second checker.
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
            -- workspace mode enables workspace-wide diagnostics pickers.
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
