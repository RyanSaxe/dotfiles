return {
  "bngarren/checkmate.nvim",
  ft = "markdown", -- Lazy loads for Markdown files matching patterns in 'files'
  opts = {
    files = {
      "todo",
      "TODO",
      "todo.md",
      "TODO.md",
      "*.todo",
      "*.todo.md",
      -- this catches my custom scratch TODO files
      "*TODO*.md",
      "*TODO*.markdown",
    },
  },
}
