-- lazydev loads type libraries on demand, which is why editing is fast —
-- but it follows MODULE dependencies, and a type dependency is not one.
-- `theme/highlights.lua` consumes `ThemeTokens` as an annotation and
-- never requires `theme`, so the editor could not resolve the class and
-- reported an undefined type plus a cascade of unknown-type warnings on
-- code that the headless check called clean.
--
-- Declaring the project's own type surface as a library keyed on the
-- word `Theme` fixes that without a fake require and without eagerly
-- indexing every installed plugin: the directory loads only for files
-- that actually mention the types.
return {
  "folke/lazydev.nvim",
  opts = {
    library = {
      { path = vim.fn.stdpath("config") .. "/lua/theme", words = { "Theme" } },
    },
  },
}
