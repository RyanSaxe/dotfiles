-- What would the editor's squiggles say? Opens the target files in this
-- headless session — real config, real language servers — and reports every
-- diagnostic they produce.
--
-- Must run as a real headless SESSION, not `nvim -l`: `-l` script mode never
-- loads plugins, so no server would ever attach and the check would pass by
-- doing nothing (see ci/editor-parity.lua, which learned this first). The
-- launcher next to this file runs
-- `nvim --headless "+luafile nvim-diagnostics.lua"` and passes options
-- through ED_* environment variables.
--
-- Files are processed in small batches — open, ask, close — the way an
-- editor session actually visits them. This is not just fidelity: ty wedges
-- its request queue when ~50 documents are open at once (0.0.48 and 0.0.72
-- both), while with a batch open every server answers in milliseconds.
--
-- Verification contract, shared with editor-parity: "could not verify" is
-- never "verified clean". Modern servers are asked directly (the LSP pull
-- model — nvim itself only pulls for the current buffer, which is why a
-- naive headless sweep sees nothing for background files); push-only
-- servers must announce each buffer via DiagnosticChanged. Any buffer no
-- server ever covered, and any server that left pulls unanswered, is named
-- in the output and the run exits 2.

local BATCH_SIZE = 10
local ATTACH_GRACE_MS = 3000 -- for remaining buffers once one client arrives
local PUSH_POLL_MS = 250
local PUSH_STABLE_POLLS = 4
local PULL_WINDOW_MS = 15000 -- per-batch ceiling; one lost reply must not eat the budget
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
    emit(("nvim-diagnostics: unknown severity %q for %s"):format(value, name))
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
        emit("nvim-diagnostics: rg --files failed for " .. target)
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
      emit("nvim-diagnostics: no such file or directory: " .. target)
      os.exit(2)
    end
  end
  if #files > MAX_FILES then
    emit(("nvim-diagnostics: %d files exceeds the %d cap; name a narrower target"):format(#files, MAX_FILES))
    os.exit(2)
  end
  return files
end

-- Ask every pull-capable client about every buffer in the batch, all
-- requests in flight at once, one shared window collecting the answers. A
-- stalled server must not discard a fast one's replies (sequential
-- all-or-nothing buf_request_sync did exactly that).
---@param buffers integer[]
---@param budget_ms integer window to wait for the batch's replies
---@return table<integer, table[]> pulled diagnostics per buffer
---@return table<integer, boolean> answered buffers with at least one pull reply
---@return table<integer, string[]> silent client names per buffer that never replied
local function pull_batch(buffers, budget_ms)
  ---@type table<integer, table[]>, table<integer, integer>
  local pulled, got_ok = {}, {}
  local outstanding = 0
  ---@type table<integer, table<string, boolean>>
  local waiting_on = {}
  for _, buffer in ipairs(buffers) do
    local params = { textDocument = vim.lsp.util.make_text_document_params(buffer) }
    for _, client in ipairs(vim.lsp.get_clients({ bufnr = buffer })) do
      if client:supports_method("textDocument/diagnostic", buffer) then
        waiting_on[buffer] = waiting_on[buffer] or {}
        waiting_on[buffer][client.name] = true
        outstanding = outstanding + 1
        client:request(
          "textDocument/diagnostic",
          params,
          ---@param err table|nil
          ---@param result {kind: string, items: table[]}|nil
          function(err, result)
            outstanding = outstanding - 1
            if err ~= nil or result == nil then
              return
            end
            got_ok[buffer] = (got_ok[buffer] or 0) + 1
            waiting_on[buffer][client.name] = nil
            for _, item in ipairs(result.kind == "full" and result.items or {}) do
              pulled[buffer] = pulled[buffer] or {}
              pulled[buffer][#pulled[buffer] + 1] = {
                lnum = item.range.start.line,
                col = item.range.start.character,
                severity = item.severity or 1,
                source = item.source,
                code = item.code,
                message = item.message,
              }
            end
          end,
          buffer
        )
      end
    end
  end
  vim.wait(
    math.max(0, budget_ms),
    ---@return boolean
    function()
      return outstanding == 0
    end,
    100
  )
  ---@type table<integer, boolean>, table<integer, string[]>
  local answered, silent = {}, {}
  for buffer, names in pairs(waiting_on) do
    answered[buffer] = (got_ok[buffer] or 0) > 0
    for name in pairs(names) do
      silent[buffer] = silent[buffer] or {}
      silent[buffer][#silent[buffer] + 1] = name
    end
  end
  return pulled, answered, silent
end

-- One string describing every diagnostic in the batch: for push-only
-- servers, "this stopped changing" is the only convergence signal there is.
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

-- Fold one batch's results into the report: pull replies (authoritative
-- where a server answered) merged with anything push-based in
-- vim.diagnostic, deduped, filtered, and sorted.
---@param report EditorDiagnosticsReport
---@param buffers integer[]
---@param pulled table<integer, table[]>
---@param min_severity integer|nil
local function fold_batch(report, buffers, pulled, min_severity)
  for _, buffer in ipairs(buffers) do
    local merged, seen = {}, {}
    for _, list in ipairs({ pulled[buffer] or {}, vim.diagnostic.get(buffer) }) do
      for _, d in ipairs(list) do
        local key = ("%d:%d:%d:%s"):format(d.lnum, d.col, d.severity, d.message)
        if not seen[key] and (min_severity == nil or d.severity <= min_severity) then
          seen[key] = true
          merged[#merged + 1] = d
        end
      end
    end
    if #merged > 0 then
      table.sort(
        merged,
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
      -- A retried file replaces its earlier entry; keep the summary honest.
      for _, old in ipairs(report.files[name] or {}) do
        report.summary.total = report.summary.total - 1
        report.summary[old.severity] = report.summary[old.severity] - 1
      end
      local items = {}
      for _, d in ipairs(merged) do
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
    emit("nvim-diagnostics: cannot write " .. path .. ": " .. tostring(err))
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
  local timeout_ms = env_number("ED_TIMEOUT", 120) * 1000
  local min_severity = env_severity("ED_MIN_SEVERITY")
  local fail_on = env_severity("ED_FAIL_ON")
  local json_path = vim.env.ED_JSON

  local files = collect_files(read_targets())
  if #files == 0 then
    emit("nvim-diagnostics: nothing to check (no files with a supported extension)")
    os.exit(2)
  end

  -- Push-based servers announce themselves per buffer through
  -- DiagnosticChanged (an empty publish still fires it).
  ---@type table<integer, boolean>
  local publish_seen = {}
  vim.api.nvim_create_autocmd("DiagnosticChanged", {
    ---@param event {buf: integer}
    callback = function(event)
      publish_seen[event.buf] = true
    end,
  })

  local started = vim.uv.hrtime()
  ---@return integer elapsed milliseconds since the check started
  local function elapsed_ms()
    return math.floor((vim.uv.hrtime() - started) / 1e6)
  end
  ---@return integer remaining milliseconds of the run's budget
  local function remaining_ms()
    return timeout_ms - elapsed_ms()
  end

  ---@param buffer integer
  ---@return boolean
  local function attached(buffer)
    return #vim.lsp.get_clients({ bufnr = buffer }) > 0
  end

  ---@type EditorDiagnosticsReport
  local report = {
    files = {},
    summary = { total = 0, ERROR = 0, WARN = 0, INFO = 0, HINT = 0 },
    unattached = {},
    verified = false,
  }
  local any_attach = false

  -- Open one batch, wait for servers, ask them, fold the answers, close the
  -- batch. Returns the files whose buffers no server covered (with the
  -- silent client names) so a flaky reply can be retried instead of either
  -- burning the whole budget or being reported as unverifiable.
  ---@param list string[]
  ---@return {file: string, silent: string[]}[] uncovered files
  local function process_files(list)
    ---@type {file: string, silent: string[]}[]
    local uncovered = {}
    ---@type integer[]
    local buffers = {}
    ---@type table<integer, string>
    local file_of = {}
    for _, file in ipairs(list) do
      vim.cmd.edit(vim.fn.fnameescape(file))
      local buffer = vim.api.nvim_get_current_buf()
      buffers[#buffers + 1] = buffer
      file_of[buffer] = file
    end

    -- Attach: wait for the first client (spawn cost, first batch only),
    -- then a short grace for the rest of the batch.
    vim.wait(
      math.max(0, remaining_ms()),
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
    vim.wait(
      math.min(ATTACH_GRACE_MS, math.max(0, remaining_ms())),
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

    -- A short settle only when some attached client cannot be pulled —
    -- push responses are the only thing worth waiting for here.
    local has_push_only = false
    for _, buffer in ipairs(buffers) do
      for _, client in ipairs(vim.lsp.get_clients({ bufnr = buffer })) do
        if not client:supports_method("textDocument/diagnostic", buffer) then
          has_push_only = true
        end
      end
    end
    if has_push_only then
      local previous, unchanged = nil, 0
      while remaining_ms() > 0 and unchanged < PUSH_STABLE_POLLS do
        vim.wait(PUSH_POLL_MS)
        local current = signature(buffers)
        unchanged = current == previous and unchanged + 1 or 0
        previous = current
      end
    end

    local pulled, answered, silent = pull_batch(buffers, math.min(PULL_WINDOW_MS, math.max(0, remaining_ms())))

    for _, buffer in ipairs(buffers) do
      if not attached(buffer) then
        report.unattached[#report.unattached + 1] = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buffer), ":.")
      else
        any_attach = true
        if not answered[buffer] and not publish_seen[buffer] then
          uncovered[#uncovered + 1] = { file = file_of[buffer], silent = silent[buffer] or {} }
        elseif silent[buffer] ~= nil then
          -- Covered by someone, but a pull-capable server stayed silent:
          -- that server's view of this file is still missing.
          uncovered[#uncovered + 1] = { file = file_of[buffer], silent = silent[buffer] }
        end
      end
    end

    fold_batch(report, buffers, pulled, min_severity)

    -- Close the batch (didClose) so the open-document count stays at what a
    -- real editing session looks like; servers wedge far above it.
    for _, buffer in ipairs(buffers) do
      pcall(vim.api.nvim_buf_delete, buffer, { force = true })
    end
    return uncovered
  end

  ---@type {file: string, silent: string[]}[]
  local uncovered = {}
  local ran_out = false
  for batch_start = 1, #files, BATCH_SIZE do
    if remaining_ms() <= 0 then
      ran_out = true
      break
    end
    ---@type string[]
    local batch = {}
    for index = batch_start, math.min(batch_start + BATCH_SIZE - 1, #files) do
      batch[#batch + 1] = files[index]
    end
    vim.list_extend(uncovered, process_files(batch))
  end

  -- One retry round: a single lost reply should cost one extra batch, not
  -- the run's verdict.
  if #uncovered > 0 and not ran_out and remaining_ms() > 5000 then
    ---@type string[]
    local retry = {}
    for _, entry in ipairs(uncovered) do
      retry[#retry + 1] = entry.file
    end
    uncovered = process_files(retry)
  end

  if not any_attach then
    emit("nvim-diagnostics: no language server attached to any target — cannot verify anything")
    os.exit(2)
  end

  report.verified = not ran_out and #report.unattached == 0 and #uncovered == 0
  if ran_out then
    emit(("nvim-diagnostics: ran out of budget after %ds; results are partial"):format(timeout_ms / 1000))
  end
  for _, entry in ipairs(uncovered) do
    local who = #entry.silent > 0 and table.concat(entry.silent, ", ") or "no server"
    emit(("nvim-diagnostics: %s — %s never answered; this file is not verified"):format(entry.file, who))
  end
  print_report(report)
  if json_path ~= nil and json_path ~= "" then
    write_json(report, json_path)
  end

  if fail_on ~= nil and report.summary.total > 0 then
    for index = 1, fail_on do
      if (report.summary[SEVERITY_NAMES[index]] or 0) > 0 then
        os.exit(1)
      end
    end
  end
  os.exit(report.verified and 0 or 2)
end, 50)
