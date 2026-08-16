-- Web language support via LazyVim extras: vtsls + eslint for TS/JS,
-- tailwind class tooling, JSON schemas. The extras install their own
-- servers through mason.
return {
  { import = "lazyvim.plugins.extras.lang.typescript" },
  { import = "lazyvim.plugins.extras.lang.tailwind" },
  { import = "lazyvim.plugins.extras.lang.json" },
}
