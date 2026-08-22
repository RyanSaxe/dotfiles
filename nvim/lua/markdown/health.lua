-- What the Markdown surface needs from outside Neovim: the Tree-sitter parsers
-- render-markdown renders from, and the executables it shells out to for
-- LaTeX. Markdown still edits without either, so both report as warnings.
local M = {}

-- render-markdown's own render paths: markdown and markdown_inline always,
-- then one per enabled element (html, latex, yaml frontmatter).
---@type string[]
local PARSERS = { "markdown", "markdown_inline", "html", "latex", "yaml" }

-- Tried in order; the first one present wins.
---@type string[]
local LATEX_CONVERTERS = { "utftex", "latex2text" }

---@param lang string
local function check_parser(lang)
  local ok, added = pcall(vim.treesitter.language.add, lang)
  if ok and added then
    vim.health.ok(("parser installed: %s"):format(lang))
  else
    vim.health.warn(("parser missing: %s"):format(lang), {
      ("run `:TSInstall %s`"):format(lang),
    })
  end
end

local function check_latex_converter()
  for _, converter in ipairs(LATEX_CONVERTERS) do
    if vim.fn.executable(converter) == 1 then
      vim.health.ok(("LaTeX converter installed: %s"):format(converter))
      return
    end
  end
  vim.health.warn(("no LaTeX converter on PATH: %s"):format(table.concat(LATEX_CONVERTERS, ", ")), {
    "macOS: `brew install utftex`",
    "elsewhere: `uv tool install pylatexenc`, which provides latex2text",
    "or set `latex = { enabled = false }` on render-markdown",
  })
end

function M.check()
  vim.health.start("markdown")

  for _, lang in ipairs(PARSERS) do
    check_parser(lang)
  end

  check_latex_converter()
end

return M
