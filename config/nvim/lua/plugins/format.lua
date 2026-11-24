-- Formatting on top of LazyVim's conform defaults (stylua for lua,
-- shfmt for shell come with the floor).
-- Python is static ruff: projects that want different tools configure
-- ruff in their own pyproject.
--
-- oxfmt formats web files and rumdl formats and lints Markdown, except in a
-- project that still has a config for the tool each replaces and none for
-- the new one. rumdl reads a markdownlint-cli2 config, but drops one with a
-- trailing comma, which JSONC allows, and can't read a .cjs or .mjs one.
--
-- oxfmt's own defaults are 100 columns and sorted package.json keys, so a
-- project without an oxfmt config gets Prettier's 80 columns and key order
-- from oxfmt/defaults.json, or only the key order when its .editorconfig
-- sets a line length.
local web_filetypes = {
  "css",
  "graphql",
  "handlebars",
  "html",
  "javascript",
  "javascriptreact",
  "json",
  "jsonc",
  "less",
  "scss",
  "typescript",
  "typescriptreact",
  "vue",
  "yaml",
}

local oxfmt_configs = { ".oxfmtrc.json", ".oxfmtrc.jsonc", "oxfmt.config.ts", "oxfmt.config.mts" }

---@param name string
---@param dir string
local function is_prettier_config(name, dir)
  if name == "package.json" then
    local ok, package = pcall(vim.json.decode, table.concat(vim.fn.readfile(dir .. "/package.json"), "\n"))
    return ok and type(package) == "table" and package.prettier ~= nil
  end
  return name:match("^%.prettierrc") ~= nil or name:match("^prettier%.config%.") ~= nil
end

---@param name string
local function is_markdownlint_cli2_config(name)
  return name:match("^%.markdownlint%-cli2%.") ~= nil
end

---@param file string
local function has_prettier_config(file)
  return vim.fs.root(file, is_prettier_config) ~= nil
end

---@param pyproject string
local function configures_rumdl(pyproject)
  for _, line in ipairs(vim.fn.readfile(pyproject)) do
    if line:match("^%[tool%.rumdl") ~= nil then
      return true
    end
  end
  return false
end

---Looks for rumdl's config files in rumdl's order, in each folder above the
---file. rumdl stops at a git repository's root, so in the vault's private/,
---a repository of its own, it would miss the vault's .rumdl.toml. This keeps
---looking, as Prettier does.
---@param file string
---@return string? path
local function rumdl_config(file)
  for dir in vim.fs.parents(file) do
    for _, name in ipairs({ ".rumdl.toml", "rumdl.toml", ".config/rumdl.toml", "pyproject.toml" }) do
      local path = vim.fs.joinpath(dir, name)
      if vim.uv.fs_stat(path) and (name ~= "pyproject.toml" or configures_rumdl(path)) then
        return path
      end
    end
  end
end

-- rumdl's other fixes change what a note says, such as a heading's level or a
-- code block's language.
local layout_fixes = {
  "MD004",
  "MD005",
  "MD007",
  "MD009",
  "MD010",
  "MD012",
  "MD013",
  "MD019",
  "MD020",
  "MD021",
  "MD022",
  "MD023",
  "MD027",
  "MD030",
  "MD031",
  "MD032",
  "MD035",
  "MD047",
  "MD048",
  "MD049",
  "MD050",
  "MD055",
  "MD058",
  "MD060",
  "MD064",
  "MD065",
  "MD071",
  "MD076",
  "MD077",
  "MD085",
}

---Names the file's rumdl config, or limits a project without one to layout
---fixes.
---@param file string
local function rumdl_config_option(file)
  return "--config=" .. (rumdl_config(file) or ("global.fixable = " .. vim.json.encode(layout_fixes)))
end

---@param buf integer
local function web_formatters(buf)
  local file = vim.api.nvim_buf_get_name(buf)
  if has_prettier_config(file) and not vim.fs.root(file, oxfmt_configs) then
    return { "prettier" }
  end
  return { "oxfmt" }
end

---@param buf integer
local function markdown_formatters(buf)
  local file = vim.api.nvim_buf_get_name(buf)
  local formatter = "rumdl"
  if has_prettier_config(file) and not rumdl_config(file) then
    formatter = "prettier"
  end
  return { formatter, "markdownlint-cli2", "markdown-toc" }
end

---@param file string
local function lints_with_markdownlint(file)
  return vim.fs.root(file, is_markdownlint_cli2_config) ~= nil and not rumdl_config(file)
end

return {
  {
    "stevearc/conform.nvim",
    opts = function(_, opts)
      opts.formatters_by_ft.python = { "ruff_organize_imports", "ruff_format" }
      opts.formatters_by_ft.zsh = { "shfmt" }
      for _, ft in ipairs(web_filetypes) do
        opts.formatters_by_ft[ft] = web_formatters
      end
      opts.formatters_by_ft.markdown = markdown_formatters
      opts.formatters_by_ft["markdown.mdx"] = markdown_formatters

      opts.formatters.oxfmt = function(buf)
        local oxfmt = {
          -- oxfmt reads .prettierignore in its working directory and
          -- .editorconfig from there up, so it runs at the project's root.
          cwd = function(_, ctx)
            return vim.fs.root(ctx.filename, { oxfmt_configs, ".git" }) or ctx.dirname
          end,
        }
        if not vim.fs.root(buf, oxfmt_configs) then
          local editorconfig = vim.b[buf].editorconfig or {}
          local defaults = editorconfig.max_line_length and "defaults-without-width.json" or "defaults.json"
          local config_dir = vim.fn.stdpath("config") --[[@as string]]
          oxfmt.prepend_args = { "--config", vim.fs.joinpath(config_dir, "oxfmt", defaults) }
        end
        return oxfmt
      end
      -- rumdl makes a .rumdl_cache folder where it runs unless told not to.
      opts.formatters.rumdl = function(buf)
        return { append_args = { "--no-cache", rumdl_config_option(vim.api.nvim_buf_get_name(buf)) } }
      end
    end,
  },
  {
    "mfussenegger/nvim-lint",
    opts = {
      linters_by_ft = { markdown = { "rumdl", "markdownlint-cli2" } },
      linters = {
        rumdl = {
          -- rumdl 0.3 prints its JSON to stdout, and nvim-lint reads stderr.
          stream = "stdout",
          -- LazyVim adds these after nvim-lint's arguments.
          prepend_args = {
            "--no-cache",
            function()
              return rumdl_config_option(vim.api.nvim_buf_get_name(0))
            end,
          },
          condition = function(ctx)
            return not lints_with_markdownlint(ctx.filename)
          end,
        },
        ["markdownlint-cli2"] = {
          condition = function(ctx)
            return lints_with_markdownlint(ctx.filename)
          end,
        },
      },
    },
  },
}
