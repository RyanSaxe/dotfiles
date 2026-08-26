-- Live diagnostics from ast-grep / byor rules while editing, instead of
-- discovering them at commit time. The server only attaches in projects
-- with an sgconfig.yml at the root (workspace_required in lspconfig's
-- definition), which is exactly the byor-managed set -- everywhere else
-- it never starts.
--
-- The binary is the extras tier's ast-grep (brew, or npm on Linux); the
-- mason entry is the usual fallback for a machine that skipped the tier
-- but opens a byor repo.
return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        ast_grep = {},
      },
    },
  },
  {
    "mason-org/mason.nvim",
    opts = { ensure_installed = { "ast-grep" } },
  },
}
