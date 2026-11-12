-- Live diagnostics from ast-grep rules while editing, instead of at commit
-- time. lspconfig starts the server at the nearest folder with an
-- sgconfig.yml: a project's own, or the home folder's, which names byor's
-- global rules. That file must be a plain file, because ast-grep reads
-- ruleDirs relative to a link's target.
--
-- packages.nix installs ast-grep, and Mason installs it on a computer that
-- lacks it.
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
