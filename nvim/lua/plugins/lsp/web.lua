-- Web development language support via LazyVim extras
-- Provides LSP, linting, and completion for TypeScript, JavaScript, Tailwind, etc.

return {
  -- TypeScript/JavaScript: vtsls LSP, eslint integration, JSX/TSX support
  { import = "lazyvim.plugins.extras.lang.typescript" },

  -- Tailwind CSS: LSP with class name completions and hover docs
  { import = "lazyvim.plugins.extras.lang.tailwind" },

  -- JSON: Schema support for package.json, tsconfig.json, etc.
  { import = "lazyvim.plugins.extras.lang.json" },
}
