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
-- Scope: ONE canary file, checked well — not a sweep of every file.
-- The divergence this guards against is workspace-level (the editor
-- missing a whole library), so one file that exercises the project's own
-- types, the vim API, and a plugin type detects it immediately.
--
-- A full sweep was tried and abandoned: opening 25 files in one session
-- keeps lazydev adding libraries as it meets new words, LuaLS re-indexes
-- under each measurement, and the run reported ~200 phantom
-- `Undefined global vim` warnings for files that are clean when opened
-- on their own. Fighting lazydev's on-demand loading to test it would
-- defeat the point of keeping it.
local script_dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
local root = vim.fs.normalize(script_dir .. "/..")

-- Uses ThemeTokens (a project class), the vim API (runtime types), and
-- catppuccin's palette (a plugin type): if any library is missing from
-- the editor's workspace, this file lights up.
local CANARY = root .. "/nvim/lua/theme/highlights.lua"

-- Generous on purpose: a cold CI runner spends its first minute
-- compiling treesitter parsers before any language server attaches.
-- Failing here means "could not verify", never "verified clean".
local ATTACH_TIMEOUT_MS = 240000
-- Diagnostics are not final when the server first answers, and no event
-- says they are; a cold lua_ls has not even loaded its own stdlib meta.
local POLL_MS = 250
local STABLE_POLLS = 8
local MAX_WAIT_MS = 40000

---@param buf integer
---@return string
local function signature(buf)
  ---@type string[]
  local parts = {}
  for _, d in ipairs(vim.diagnostic.get(buf)) do
    parts[#parts + 1] = ("%d:%d:%s"):format(d.lnum, d.col, d.message)
  end
  table.sort(parts)
  return table.concat(parts, "\n")
end

vim.defer_fn(function()
  vim.cmd.edit(vim.fn.fnameescape(CANARY))
  local buf = vim.api.nvim_get_current_buf()

  local activity_generation = 0
  ---@type table<integer, integer>
  local active_progress = {}
  local function mark_activity()
    activity_generation = activity_generation + 1
  end

  vim.api.nvim_create_autocmd({ "LspAttach", "LspDetach" }, {
    callback = mark_activity,
  })
  vim.api.nvim_create_autocmd("DiagnosticChanged", {
    ---@param event {buf: integer}
    callback = function(event)
      if event.buf == buf then
        mark_activity()
      end
    end,
  })
  vim.api.nvim_create_autocmd("LspProgress", {
    ---@param event {data: {client_id: integer, params: {value: {kind: string}}}}
    callback = function(event)
      local data = event.data
      local value = data and data.params and data.params.value
      if data and value then
        local client = vim.lsp.get_client_by_id(data.client_id)
        if client ~= nil and client.name == "lua_ls" then
          mark_activity()
          if value.kind == "begin" then
            active_progress[data.client_id] = (active_progress[data.client_id] or 0) + 1
          elseif value.kind == "end" then
            active_progress[data.client_id] = math.max(0, (active_progress[data.client_id] or 1) - 1)
            if active_progress[data.client_id] == 0 then
              active_progress[data.client_id] = nil
            end
          end
        end
      end
    end,
  })

  ---@return boolean
  local function has_client()
    return #vim.lsp.get_clients({ bufnr = buf, name = "lua_ls" }) > 0
  end
  if not vim.wait(ATTACH_TIMEOUT_MS, has_client, 100) then
    io.write("editor-parity: lua_ls never attached — the check cannot verify anything\n")
    os.exit(1)
  end

  local started = vim.uv.hrtime()
  ---@return integer remaining milliseconds in the readiness budget
  local function remaining_ms()
    return MAX_WAIT_MS - math.floor((vim.uv.hrtime() - started) / 1e6)
  end

  local previous = signature(buf)
  local previous_activity = activity_generation
  local unchanged = 0
  local settled = false
  while remaining_ms() > 0 do
    vim.wait(math.min(POLL_MS, math.max(0, remaining_ms())))
    if not has_client() or next(active_progress) ~= nil then
      unchanged = 0
    else
      local current = signature(buf)
      if current ~= previous or activity_generation ~= previous_activity then
        previous = current
        previous_activity = activity_generation
        unchanged = 0
      else
        unchanged = unchanged + 1
      end
      if unchanged >= STABLE_POLLS then
        settled = true
        break
      end
    end
  end

  if not settled then
    io.write("editor-parity: lua_ls diagnostics never settled — the check cannot verify anything\n")
    os.exit(1)
  end

  local diagnostics = vim.diagnostic.get(buf)
  if #diagnostics == 0 then
    io.write("editor-parity: the editor reports nothing on " .. CANARY:sub(#root + 2) .. "\n")
    os.exit(0)
  end

  for _, d in ipairs(diagnostics) do
    io.write(
      ("%s:%d:%d: [%s] %s\n"):format(
        CANARY:sub(#root + 2),
        d.lnum + 1,
        d.col + 1,
        vim.diagnostic.severity[d.severity],
        d.message
      )
    )
  end
  io.write(("editor-parity: %d diagnostic(s) the editor shows and the headless check misses\n"):format(#diagnostics))
  os.exit(1)
end, 3000)
