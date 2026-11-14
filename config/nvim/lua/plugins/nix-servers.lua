-- nil and gopls come from Nix with the other language servers, so LazyVim
-- starts the ones on PATH instead of waiting for Mason to build them.
return {
  "neovim/nvim-lspconfig",
  opts = {
    servers = {
      gopls = { mason = false },
      nil_ls = { mason = false },
    },
  },
}
