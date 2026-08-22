-- What would the editor's squiggles say? Opens the target files in this
-- headless session — real config, real language servers — and reports every
-- diagnostic they produce.
--
-- Must run as a real headless SESSION, not `nvim -l`: `-l` script mode never
-- loads plugins, so no server would ever attach and the check would pass by
-- doing nothing (see ci/editor-parity.lua, which learned this first). The
-- launcher next to this file runs
-- `nvim --headless "+luafile editor-diagnostics.lua"` and passes options
-- through ED_* environment variables.
--
-- Verification contract, shared with editor-parity: failing to attach or to
-- settle means "could not verify" (exit 2), never "verified clean". There is
-- no LSP signal for "all diagnostics delivered", so settling is observed:
-- the combined diagnostic signature must hold still across STABLE_POLLS
-- polls, and the clock is held while any server still reports $/progress
-- work (a cold pyright indexes far longer than any quiet window).

local POLL_MS = 250
local STABLE_POLLS = 8
local STRAGGLER_MS = 3000 -- extra attach time for other buffers after the first client
local MAX_FILES = 200

-- Extensions worth opening: filetypes this setup runs language servers or
-- linters for. A directory sweep skips everything else; an explicit file
-- argument is always opened.
local EXTENSIONS = {
  lua = true,
  py = true,
  pyi = true,
  js = true,
  ts = true,
  jsx = true,
  tsx = true,
  rs = true,
  go = true,
  c = true,
  cpp = true,
  h = true,
  java = true,
  rb = true,
  sh = true,
  zsh = true,
  vim = true,
  md = true,
  toml = true,
  yaml = true,
  yml = true,
  json = true,
}

local SEVERITY_NAMES = { "ERROR", "WARN", "INFO", "HINT" }
local SEVERITY_BY_NAME = { ERROR = 1, WARN = 2, INFO = 3, HINT = 4 }

---@param message string
local function emit(message)
  io.write(message .. "\n")
end

---@param name string
---@param fallback integer
---@return integer
local function env_number(name, fallback)
  local value = tonumber(vim.env[name])
  return value or fallback
end

---@param name string
---@return integer|nil severity index, nil when the variable is unset
local function env_severity(name)
  local value = vim.env[name]
  if value == nil or value == "" then
    return nil
  end
  local severity = SEVERITY_BY_NAME[value:upper()]
  if severity == nil then
    emit(("editor-diagnostics: unknown severity %q for %s"):format(value, name))
    os.exit(2)
  end
  return severity
end

---@return string[] targets from ED_TARGETS, one per line; "." when unset
local function read_targets()
  local raw = vim.env.ED_TARGETS
  if raw == nil or raw == "" then
    return { "." }
  end
  return vim.split(raw, "\n", { trimempty = true })
end

---@param path string
---@return boolean
local function has_wanted_extension(path)
  local extension = path:match("%.([%w]+)$")
  return extension ~= nil and EXTENSIONS[extension:lower()] == true
end

-- Expand targets into the list of files to open. Directories are swept with
-- rg (so .gitignore applies) and filtered by extension; files named
-- explicitly are taken as-is.
---@param targets string[]
---@return string[]
local function collect_files(targets)
  local files, seen = {}, {}
  ---@param path string
  local function keep(path)
    if not seen[path] then
      seen[path] = true
      files[#files + 1] = path
    end
  end
  for _, target in ipairs(targets) do
    if vim.fn.isdirectory(target) == 1 then
      local listed = vim.fn.systemlist({ "rg", "--files", "--hidden", "-g", "!.git", "--", target })
      if vim.v.shell_error ~= 0 then
        emit("editor-diagnostics: rg --files failed for " .. target)
        os.exit(2)
      end
      for _, path in ipairs(listed) do
        if has_wanted_extension(path) then
          keep(path)
        end
      end
    elseif vim.fn.filereadable(target) == 1 then
      keep(target)
    else
      emit("editor-diagnostics: no such file or directory: " .. target)
      os.exit(2)
    end
  end
  if #files > MAX_FILES then
    emit(("editor-diagnostics: %d files exceeds the %d cap; name a narrower target"):format(#files, MAX_FILES))
    os.exit(2)
  end
  return files
end

-- One string describing every diagnostic in every buffer: settling is "this
-- signature stopped changing", which observes convergence directly instead
-- of guessing from update timing.
---@param buffers integer[]
---@return string
local function signature(buffers)
  ---@type string[]
  local parts = {}
  for _, buffer in ipairs(buffers) do
    for _, d in ipairs(vim.diagnostic.get(buffer)) do
      parts[#parts + 1] = ("%d:%d:%d:%s"):format(buffer, d.lnum, d.col, d.message)
    end
  end
  table.sort(parts)
  return table.concat(parts, "\n")
end

---@class EditorDiagnosticsReport
---@field files table<string, table[]>
---@field summary table<string, integer>
---@field unattached string[]
---@field verified boolean

-- Gather, filter, and sort every diagnostic at or above min_severity.
---@param buffers integer[]
---@param min_severity integer|nil
---@param unattached string[]
---@param verified boolean
---@return EditorDiagnosticsReport
local function build_report(buffers, min_severity, unattached, verified)
  local report = {
    files = {},
    summary = { total = 0, ERROR = 0, WARN = 0, INFO = 0, HINT = 0 },
    unattached = unattached,
    verified = verified,
  }
  for _, buffer in ipairs(buffers) do
    local diagnostics = vim.tbl_filter(
      ---@param d vim.Diagnostic
      ---@return boolean
      function(d)
        return min_severity == nil or d.severity <= min_severity
      end,
      vim.diagnostic.get(buffer)
    )
    if #diagnostics > 0 then
      table.sort(
        diagnostics,
        ---@param a vim.Diagnostic
        ---@param b vim.Diagnostic
        ---@return boolean
        function(a, b)
          if a.lnum ~= b.lnum then
            return a.lnum < b.lnum
          end
          return a.col < b.col
        end
      )
      local name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buffer), ":.")
      local items = {}
      for _, d in ipairs(diagnostics) do
        local severity = SEVERITY_NAMES[d.severity] or "UNKNOWN"
        items[#items + 1] = {
          line = d.lnum + 1,
          col = d.col + 1,
          severity = severity,
          source = d.source or "lsp",
          code = d.code,
          message = d.message,
        }
        report.summary.total = report.summary.total + 1
        report.summary[severity] = (report.summary[severity] or 0) + 1
      end
      report.files[name] = items
    end
  end
  return report
end

---@param report EditorDiagnosticsReport
local function print_report(report)
  ---@type string[]
  local names = vim.tbl_keys(report.files)
  table.sort(names)
  for _, name in ipairs(names) do
    for _, item in ipairs(report.files[name]) do
      emit(
        ("%s:%d:%d %s %s: %s"):format(
          name,
          item.line,
          item.col,
          item.severity,
          item.source,
          item.message:gsub("%s+", " ")
        )
      )
    end
  end
  for _, name in ipairs(report.unattached) do
    emit(name .. ": no language server attached")
  end
  local s = report.summary
  emit(
    ("%d findings (%d errors, %d warnings, %d info, %d hints)%s"):format(
      s.total,
      s.ERROR,
      s.WARN,
      s.INFO,
      s.HINT,
      report.verified and "" or " — NOT fully verified"
    )
  )
end

---@param report EditorDiagnosticsReport
---@param path string
local function write_json(report, path)
  local handle, err = io.open(path, "w")
  if handle == nil then
    emit("editor-diagnostics: cannot write " .. path .. ": " .. tostring(err))
    os.exit(2)
  end
  handle:write(vim.json.encode({
    generated = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    verified = report.verified,
    unattached = report.unattached,
    files = report.files,
    summary = report.summary,
  }))
  handle:close()
end

vim.defer_fn(function()
  local timeout_ms = env_number("ED_TIMEOUT", 60) * 1000
  local min_severity = env_severity("ED_MIN_SEVERITY")
  local fail_on = env_severity("ED_FAIL_ON")
  local json_path = vim.env.ED_JSON

  local files = collect_files(read_targets())
  if #files == 0 then
    emit("editor-diagnostics: nothing to check (no files with a supported extension)")
    os.exit(2)
  end

  -- Hold the settle clock while any server reports active $/progress work:
  -- a cold server pauses publishing while it indexes, and a quiet window
  -- alone would misread that silence as "done".
  local active_progress = 0
  vim.api.nvim_create_autocmd("LspProgress", {
    ---@param event {data: {params: {value: {kind: string}}}}
    callback = function(event)
      local kind = vim.tbl_get(event, "data", "params", "value", "kind")
      if kind == "begin" then
        active_progress = active_progress + 1
      elseif kind == "end" then
        active_progress = math.max(0, active_progress - 1)
      end
    end,
  })

  ---@type integer[]
  local buffers = {}
  for _, file in ipairs(files) do
    vim.cmd.edit(vim.fn.fnameescape(file))
    buffers[#buffers + 1] = vim.api.nvim_get_current_buf()
  end

  ---@param buffer integer
  ---@return boolean
  local function attached(buffer)
    return #vim.lsp.get_clients({ bufnr = buffer }) > 0
  end

  -- Attach phase: at least one server must arrive or nothing was verified.
  -- Stragglers get a short extra window; buffers still serverless after it
  -- are reported as such rather than silently counted clean.
  local started = vim.uv.hrtime()
  ---@return integer elapsed milliseconds since the check started
  local function elapsed_ms()
    return math.floor((vim.uv.hrtime() - started) / 1e6)
  end

  local any_attached = vim.wait(
    timeout_ms,
    ---@return boolean
    function()
      for _, buffer in ipairs(buffers) do
        if attached(buffer) then
          return true
        end
      end
      return false
    end,
    100
  )
  if not any_attached then
    emit("editor-diagnostics: no language server attached to any target — cannot verify anything")
    os.exit(2)
  end
  vim.wait(
    STRAGGLER_MS,
    ---@return boolean
    function()
      for _, buffer in ipairs(buffers) do
        if not attached(buffer) then
          return false
        end
      end
      return true
    end,
    100
  )

  ---@type string[]
  local unattached = {}
  for _, buffer in ipairs(buffers) do
    if not attached(buffer) then
      unattached[#unattached + 1] = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buffer), ":.")
    end
  end

  -- Settle phase: the diagnostic signature must hold still, with the
  -- stability counter frozen while servers report progress.
  local previous, unchanged = nil, 0
  local settled = false
  while elapsed_ms() < timeout_ms do
    vim.wait(POLL_MS)
    if active_progress == 0 then
      local current = signature(buffers)
      unchanged = current == previous and unchanged + 1 or 0
      previous = current
      if unchanged >= STABLE_POLLS then
        settled = true
        break
      end
    end
  end

  local verified = settled and #unattached == 0
  local report = build_report(buffers, min_severity, unattached, verified)
  if not settled then
    emit(("editor-diagnostics: diagnostics did not settle within %ds"):format(timeout_ms / 1000))
  end
  print_report(report)
  if json_path ~= nil and json_path ~= "" then
    write_json(report, json_path)
  end

  if fail_on ~= nil and (report.summary.total > 0) then
    for index = 1, fail_on do
      if (report.summary[SEVERITY_NAMES[index]] or 0) > 0 then
        os.exit(1)
      end
    end
  end
  os.exit(verified and 0 or 2)
end, 50)
