-- "If the editor would show it, CI fails." The other Lua checks run
-- lua-language-server directly; this one asks the ACTUAL editor — real
-- config, real lua_ls, real lazydev — and fails on any diagnostic it
-- reports.
--
-- This exists because the two disagreed silently for a long time. The
-- headless check built a rich library list at runtime while
-- `.luarc.json` named `$VIMRUNTIME/lua`, a placeholder only that script
-- expanded, so the editor ran with no vim runtime types and showed
-- hundreds of `Cannot infer type` warnings on code CI called clean.
-- Nothing caught it; someone had to open a file and notice. Now opening
-- the files IS the check.
--
-- Must run as a real headless SESSION, not `nvim -l`: `-l` script mode
-- never loads plugins, so no language server ever attaches and the check
-- would pass by doing nothing. Run via
-- `nvim --headless -c 'luafile dev/editor-parity.lua'`.
--
-- Each file is opened and waited on individually, which is what makes
-- this slow. Batching — `bufload` everything then settle once — does not
-- work: lua_ls does not reliably attach to buffers that were never
-- displayed, and the check hangs waiting for a client that never comes.
local script_dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
local root = vim.fs.normalize(script_dir .. "/..")
local lua_root = root .. "/nvim/dot-config/nvim/lua"

-- Generous: a cold lua_ls indexes every plugin library on first attach.
local ATTACH_TIMEOUT_MS = 60000
local SETTLE_MS = 1500

---@return string[]
local function targets()
  return vim.fn.glob(lua_root .. "/**/*.lua", true, true)
end

---@param path string
---@return vim.Diagnostic[]
local function diagnose(path)
  vim.cmd.edit(vim.fn.fnameescape(path))
  local buf = vim.api.nvim_get_current_buf()
  ---@return boolean
  local function has_client()
    return #vim.lsp.get_clients({ bufnr = buf, name = "lua_ls" }) > 0
  end
  local attached = vim.wait(ATTACH_TIMEOUT_MS, has_client, 100)
  if not attached then
    error("lua_ls never attached to " .. path .. " — the check cannot verify anything")
  end
  -- No event says "diagnostics are final"; let the server settle.
  vim.wait(SETTLE_MS)
  return vim.diagnostic.get(buf)
end

-- Deferred so lazy.nvim has finished loading before the first file opens.
vim.defer_fn(function()
  ---@type string[]
  local findings = {}
  local paths = targets()
  for _, path in ipairs(paths) do
    for _, d in ipairs(diagnose(path)) do
      findings[#findings + 1] = ("%s:%d:%d: [%s] %s"):format(
        path:sub(#root + 2),
        d.lnum + 1,
        d.col + 1,
        vim.diagnostic.severity[d.severity],
        d.message
      )
    end
  end

  if #findings == 0 then
    io.write(("editor-parity: %d files, no diagnostics in a live editor\n"):format(#paths))
    os.exit(0)
  end

  table.sort(findings)
  for _, finding in ipairs(findings) do
    io.write(finding, "\n")
  end
  io.write(("editor-parity: %d diagnostic(s) the editor shows\n"):format(#findings))
  os.exit(1)
end, 3000)
