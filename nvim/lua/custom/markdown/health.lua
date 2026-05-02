local M = {}

local function executable(name)
  return vim.fn.executable(name) == 1
end

local function check_parser(lang)
  local ok = pcall(vim.treesitter.language.inspect, lang)
  if ok then
    vim.health.ok(("Tree-sitter parser installed: %s"):format(lang))
  else
    vim.health.warn(("Tree-sitter parser missing: %s"):format(lang), {
      "LazyVim should install this from nvim-treesitter.ensure_installed.",
      "Run :Lazy sync or restart Neovim after updating plugins.",
    })
  end
end

local function check_dir(label, path)
  local expanded = vim.fn.expand(path)
  if vim.uv.fs_stat(expanded) then
    vim.health.ok(("%s exists: %s"):format(label, expanded))
  else
    vim.health.warn(("%s is missing: %s"):format(label, expanded), {
      "Run scripts/setup-notes.sh to scaffold the new vault.",
    })
  end
end

function M.check()
  vim.health.start("Markdown / Obsidian")

  for _, lang in ipairs({ "markdown", "markdown_inline", "html", "yaml", "latex" }) do
    check_parser(lang)
  end

  if executable("utftex") then
    vim.health.ok("LaTeX converter installed: utftex")
  elseif executable("latex2text") then
    vim.health.ok("LaTeX converter installed: latex2text")
  else
    vim.health.warn("No render-markdown LaTeX converter found", {
      "Run scripts/install.sh to install utftex on macOS or latex2text via pylatexenc on Linux.",
    })
  end

  check_dir("Notes vault", "~/generic/notes")
end

return M
