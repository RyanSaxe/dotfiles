-- What the Markdown surface needs from outside Neovim: the Tree-sitter parsers
-- render-markdown and snacks read, and the programs snacks runs to draw
-- pictures, diagrams and math. Markdown still edits without any of them, so
-- each reports as a warning.
local M = {}

-- markdown and markdown_inline always, html and yaml for render-markdown's
-- comments and frontmatter, and latex for the math snacks finds.
---@type string[]
local PARSERS = { "markdown", "markdown_inline", "html", "latex", "yaml" }

-- Each program snacks runs, and what it draws, from plugins/images.lua.
---@type { [1]: string, [2]: string }[]
local PROGRAMS = {
  { "magick", "any picture" },
  { "mmdc", "Mermaid diagrams" },
  { "pdflatex", "math" },
}

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

function M.check()
  vim.health.start("markdown")

  for _, lang in ipairs(PARSERS) do
    check_parser(lang)
  end

  for _, program in ipairs(PROGRAMS) do
    local name, draws = program[1], program[2]
    if vim.fn.executable(name) == 1 then
      vim.health.ok(("%s installed, for %s"):format(name, draws))
    else
      vim.health.warn(("%s missing, so snacks can't draw %s"):format(name, draws), {
        "modules/home/packages.nix installs it at a home switch",
      })
    end
  end
end

return M
