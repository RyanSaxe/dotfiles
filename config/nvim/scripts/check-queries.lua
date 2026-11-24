-- Parses each queries/LANG/context.scm of a Neovim config together with
-- nvim-treesitter-context's own context query for LANG, the way Neovim
-- loads them, and fails if any of them does not parse. Languages with no
-- parser installed cannot be parsed, so they are listed as unchecked.
--
-- usage: nvim --clean --headless -l check-queries.lua [CONFIG_DIR] [RUNTIME_DIR...]
--   CONFIG_DIR   the config that holds queries/ (default: stdpath("config"))
--   RUNTIME_DIR  more directories with parser/ to add to 'runtimepath'
local default_config = vim.fn.stdpath("config") --[[@as string]]
local config_dir = vim.fs.normalize(arg[1] or default_config)
local data_dir = vim.fn.stdpath("data") --[[@as string]]
local context_plugin = data_dir .. "/lazy/nvim-treesitter-context"
if not vim.uv.fs_stat(context_plugin .. "/queries") then
  io.stderr:write(("nvim-treesitter-context is not installed at %s\n"):format(context_plugin))
  os.exit(2)
end

vim.opt.runtimepath:prepend(config_dir)
vim.opt.runtimepath:append(data_dir .. "/site")
vim.opt.runtimepath:append(context_plugin)
for i = 2, #arg do
  vim.opt.runtimepath:append(vim.fs.normalize(arg[i]))
end

---@param path string
---@return string
local function real(path)
  return vim.uv.fs_realpath(path) or path
end

---@param file string
---@param unchecked string[]
---@return boolean failed
local function check_query(file, unchecked)
  local lang = vim.fn.fnamemodify(file, ":h:t")
  if not vim.treesitter.language.add(lang) then
    unchecked[#unchecked + 1] = lang
    return false
  end
  local loaded = vim.tbl_map(real, vim.treesitter.query.get_files(lang, "context"))
  local ok, query = pcall(vim.treesitter.query.get, lang, "context")
  if not vim.list_contains(loaded, real(file)) then
    io.stdout:write(("FAIL %s: Neovim does not load %s\n"):format(lang, file))
    return true
  elseif not ok then
    io.stdout:write(("FAIL %s: %s\n"):format(lang, query))
    return true
  end
  io.stdout:write(("ok   %s, from %d files\n"):format(lang, #loaded))
  return false
end

local files = vim.fn.glob(config_dir .. "/queries/*/context.scm", false, true)
table.sort(files)
if #files == 0 then
  io.stderr:write(("no queries/*/context.scm in %s\n"):format(config_dir))
  os.exit(2)
end

local failed, unchecked = false, {} ---@type boolean, string[]
for _, file in ipairs(files) do
  if check_query(file, unchecked) then
    failed = true
  end
end
if #unchecked > 0 then
  io.stdout:write(("unchecked, no parser: %s\n"):format(table.concat(unchecked, ", ")))
end
os.exit(failed and 1 or 0)
