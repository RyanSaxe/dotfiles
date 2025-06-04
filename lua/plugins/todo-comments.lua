-- enable TODOs to still work when people are assigned to them
return {
  "folke/todo-comments.nvim",
  opts = {
    highlight = {
      pattern = { [[.*<(KEYWORDS)\s*:]], [[.*<(KEYWORDS)\s*\(.*\)\s*:]] },
    },
    -- NOTE: this may not cover all tagged cases, so if you come across issues, update the regex
    search = {
      -- the “KEYWORDS” token will be replaced by whatever keywords you’ve configured (TODO, FIX, etc)
      -- the part after \b(KEYWORDS)\b says:
      --   (?:\s*\([^)]+\)    →   optionally “(anything)” after the keyword
      --    | \s+@[^\s:]+    →   or a space + “@username” without colon/space in the username
      -- )?                 →   make that whole “(…|…)” block optional
      -- \s*:               →   then some whitespace, then a literal colon
      pattern = [[\b(KEYWORDS)\b(?:\s*\([^)]+\)|\s+@[^\s:]+)?\s*:]],
    },
  },
}
