return {
  "neovim/nvim-lspconfig",
  opts = {
    servers = {
      basedpyright = {
        settings = {
          basedpyright = {
            analysis = {
              typeCheckingMode = "basic",
              inlayHints = {
                variableTypes = true,
                callArgumentNames = true,
                functionReturnTypes = true,
                genericTypes = true,
              },
              diagnosticMode = "openFilesOnly", --"workspace" if the entire project. Can be slow.
              exclude = { ".venv", "venv" },
              autoImportCompletions = true,
              autoSearchPaths = true,
            },
          },
        },
      },
    },
  },
}
