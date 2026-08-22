-- Keywords stay recognizable once a person is attached to them:
-- `TODO(@person):` and `TODO @person:` both count. Highlight and search have
-- to widen together — a highlight-only widening paints comments the picker
-- cannot find.
--
-- Search and navigation stay LazyVim's: `<leader>st` / `<leader>sT` (snacks
-- picker), `<leader>xt` / `<leader>xT` (trouble), `]t` / `[t` (jump). Nothing
-- is rebound here.
--
-- This is a code tool. `TODO:` markers in source files get this picker; they
-- are not Markdown tasks and never become one.
return {
  "folke/todo-comments.nvim",
  opts = {
    -- Vim regexes, matched with `\v\C`: bare keyword, parenthesized assignee,
    -- bare `@assignee`.
    highlight = {
      pattern = {
        [[.*<(KEYWORDS)\s*:]],
        [[.*<(KEYWORDS)\s*\(.*\)\s*:]],
        [[.*<(KEYWORDS)\s+\@\S+\s*:]],
      },
    },
    -- One ripgrep regex covering the same three: the keyword, then optionally
    -- `(anything)` or ` @assignee`, then the colon.
    search = {
      pattern = [[\b(KEYWORDS)\b(?:\s*\([^)]+\)|\s+@[^\s:]+)?\s*:]],
    },
  },
}
