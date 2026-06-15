-- ast-grep: live in-editor diagnostics from your ast-grep / byor rules.
--
-- Attaches in any project with an `sgconfig.yml` at its root (every `byor init`
-- repo writes one), surfacing project, local, and mirrored-global rules as you
-- type — the same diagnostics `ast-grep scan` and `byor agent-check` report.
--
-- mason installs the `ast-grep` binary (see lsp/mason.lua); this just enables the
-- LSP. Quick-fixes (suppress, rewrites) appear as code actions where rules define them.

return {
  "neovim/nvim-lspconfig",
  opts = {
    servers = {
      ast_grep = {},
    },
  },
}
