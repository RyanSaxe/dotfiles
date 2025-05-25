--lsp customizations
--another comment
return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        basedpyright = {
          settings = {
            basedpyright = {
              analysis = {
                typeCheckingMode = "basic",
                inlayHints = true,
              },
            },
          },
        },
      },
    },
  },
}
