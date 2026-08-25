-- Headless Lua typecheck: the same lua-language-server the editor runs,
-- with the nvim runtime and every installed plugin as typed libraries
-- (lazydev's job, done statically). Run via `nvim -l dev/luals-check.lua`.
--
-- Skips cleanly where lua-language-server is not installed: the Lua
-- toolchain is mac-only (see install.sh), and CI installs it explicitly.
if vim.fn.executable("lua-language-server") == 0 then
  print("luals-check: lua-language-server not installed, skipping")
  os.exit(0)
end

local script_dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
local config_dir = vim.fs.normalize(script_dir .. "/../nvim")

---@type table<string, any>
local luarc = vim.json.decode(table.concat(vim.fn.readfile(config_dir .. "/.luarc.json"), "\n"))

-- This run has no lazydev, so it stands in for it: the vim runtime plus
-- every installed plugin's lua dir. The EDITOR must never be given this
-- list — lazydev fetches those on demand, and eagerly indexing 45
-- plugins on every attach makes editing crawl. `.luarc.json` holds only
-- the diagnostic policy, which both sides share; it must not name
-- libraries, because LuaLS gives it precedence over client settings and
-- a stale entry there silently overrides lazydev.
---@type string[]
local library = { vim.env.VIMRUNTIME .. "/lua" }
local data_home = vim.env.XDG_DATA_HOME or (vim.env.HOME .. "/.local/share")
vim.list_extend(library, vim.fn.glob(data_home .. "/nvim/lazy/*/lua", true, true))
luarc["workspace.library"] = library

local generated = vim.fn.tempname() .. ".luarc.json"
vim.fn.writefile({ vim.json.encode(luarc) }, generated)

-- Trace logging, kept on permanently rather than added when something
-- goes wrong. This check has failed CI once on a file the triggering PR
-- never touched and passed on rerun, and the obvious explanation -- a
-- short plugin library degrading inference -- was tested and is wrong.
-- An intermittent failure that leaves no evidence cannot be diagnosed
-- after the fact, so the next occurrence has to explain itself. Set
-- LUALS_LOGPATH to collect it somewhere durable; CI does.
local logpath = vim.env.LUALS_LOGPATH or (vim.fn.tempname() .. ".luals-log")

local result = vim
  .system({
    "lua-language-server",
    "--check",
    config_dir,
    "--checklevel=Warning",
    "--configpath",
    generated,
    "--loglevel=trace",
    "--logpath=" .. logpath,
  })
  :wait()
io.write(result.stdout or "", result.stderr or "")
if result.code ~= 0 then
  io.write(("luals-check: trace log written to %s\n"):format(logpath))
end
os.exit(result.code)
