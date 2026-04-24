-- Harper: Grammar and spell checker for developers
-- Replaces Vim's built-in spell checking with LSP-based diagnostics
-- Mason auto-installs harper-ls when this config is loaded
--
-- Dictionary is managed via dotfiles symlink:
-- ~/generic/dotfiles/harper/dictionary.txt -> ~/.config/harper-ls/dictionary.txt
--
-- Add words to dictionary via code actions (<leader>ca on a flagged word)
--
-- By default, Harper only auto-attaches to prose filetypes (markdown, text, etc.)
-- Use <leader>tg to manually enable Harper for any buffer (e.g., code files)

-- Filetypes where Harper auto-attaches
-- currently disabled by default because it's pretty annoying
local prose_filetypes = {
  -- "markdown",
  -- "text",
  -- "gitcommit",
  -- "mail",
  -- "plaintex",
  -- "tex",
  -- "asciidoc",
  -- "rst",
  -- "org",
}

return {
  "neovim/nvim-lspconfig",
  opts = {
    servers = {
      harper_ls = {
        -- Only auto-attach to prose filetypes
        -- Use <leader>tg to manually start Harper in code files
        filetypes = prose_filetypes,
        settings = {
          ["harper-ls"] = {
            linters = {
              -- Disable sentence capitalization - too noisy in code comments
              -- where sentences often start with lowercase identifiers
              SentenceCapitalization = false,
            },
            -- Use hint severity to keep diagnostics non-intrusive
            -- Errors/warnings should be reserved for actual code issues
            diagnosticSeverity = "hint",
            -- American English dialect (options: American, British, Canadian, Australian)
            dialect = "American",
          },
        },
      },
    },
  },
}
