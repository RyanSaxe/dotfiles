local M = {}

local state = {
  active = {}, -- [client_id] = { [token] = true }
}

local function ensure_client_bucket(client_id)
  state.active[client_id] = state.active[client_id] or {}
  return state.active[client_id]
end

local function progress_token(ev)
  return ev.data.params.token
end

local function progress_value(ev)
  return ev.data.params.value or {}
end

local function client_names(clients)
  local names = {}
  for _, client in ipairs(clients or {}) do
    table.insert(names, client.name)
  end
  table.sort(names)
  return names
end

local function notify_no_support(clients, action)
  local names = client_names(clients)

  local msg
  if #names == 0 then
    msg = ("No LSPs attached for %s"):format(action)
  else
    msg = ("None of [%s] support %s"):format(table.concat(names, ", "), action)
  end

  vim.notify(msg, vim.log.levels.WARN, { title = "Diagnostics" })
end

local function get_attached_clients(bufnrs)
  local seen = {}
  local clients = {}

  for _, bufnr in ipairs(bufnrs) do
    for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
      if not seen[client.id] then
        seen[client.id] = true
        table.insert(clients, client)
      end
    end
  end

  return clients
end

local function supports_workspace(client)
  return client:supports_method("workspace/diagnostic")
end

local function supports_document(client, bufnr)
  return client:supports_method("textDocument/diagnostic", bufnr)
end

local function make_buf_set(bufnrs)
  local set = {}
  for _, bufnr in ipairs(bufnrs) do
    set[bufnr] = true
  end
  return set
end

local function is_normal_open_buffer(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end
  if not vim.api.nvim_buf_is_loaded(bufnr) then
    return false
  end
  if not vim.bo[bufnr].buflisted then
    return false
  end
  if vim.bo[bufnr].buftype ~= "" then
    return false
  end
  return vim.api.nvim_buf_get_name(bufnr) ~= ""
end

local function get_open_file_bufnrs()
  local bufnrs = {}
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if is_normal_open_buffer(bufnr) then
      table.insert(bufnrs, bufnr)
    end
  end
  return bufnrs
end

local function relevant_workspace_clients(bufnrs)
  local clients = get_attached_clients(bufnrs)
  local supported = {}

  for _, client in ipairs(clients) do
    if supports_workspace(client) then
      table.insert(supported, client)
    end
  end

  return clients, supported
end

local function relevant_document_clients(bufnrs)
  local clients = get_attached_clients(bufnrs)
  local supported_map = {}

  for _, bufnr in ipairs(bufnrs) do
    for _, client in ipairs(clients) do
      if supports_document(client, bufnr) then
        supported_map[client.id] = client
      end
    end
  end

  local supported = {}
  for _, client in ipairs(clients) do
    if supported_map[client.id] then
      table.insert(supported, client)
    end
  end

  return clients, supported
end

local function request_workspace_diagnostics(bufnrs)
  local clients, supported = relevant_workspace_clients(bufnrs)
  local requested = false

  for _, client in ipairs(supported) do
    vim.lsp.buf.workspace_diagnostics({ client_id = client.id })
    requested = true
  end

  return requested, clients, supported
end

local function request_document_diagnostics(bufnrs)
  local clients, supported = relevant_document_clients(bufnrs)
  local requested = false

  for _, bufnr in ipairs(bufnrs) do
    local params = vim.lsp.util.make_text_document_params(bufnr)
    for _, client in ipairs(supported) do
      if supports_document(client, bufnr) then
        client:request("textDocument/diagnostic", params, function() end, bufnr)
        requested = true
      end
    end
  end

  return requested, clients, supported
end

local function snacks_open(opts)
  Snacks.picker.diagnostics(opts or {})
end

local function open_files_filter(bufnrs)
  local buf_set = make_buf_set(bufnrs)

  return function(item)
    if item.buf and buf_set[item.buf] then
      return true
    end

    if type(item.file) == "string" and item.file ~= "" then
      for _, bufnr in ipairs(bufnrs) do
        if vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_get_name(bufnr) == item.file then
          return true
        end
      end
    end

    return false
  end
end

local function tracker_for_clients(clients)
  local client_set = {}
  for _, client in ipairs(clients or {}) do
    client_set[client.id] = true
  end

  return {
    client_set = client_set,
    started = {}, -- [client_id] = { [token] = true }
  }
end

local function tracker_has_started(tracker)
  for _, tokens in pairs(tracker.started) do
    if next(tokens) ~= nil then
      return true
    end
  end
  return false
end

local function tracker_is_done(tracker)
  for client_id, started_tokens in pairs(tracker.started) do
    local active_tokens = state.active[client_id] or {}
    for token, _ in pairs(started_tokens) do
      if active_tokens[token] then
        return false
      end
    end
  end
  return true
end

function M.on_progress(ev)
  local client_id = ev.data.client_id
  local token = progress_token(ev)
  local value = progress_value(ev)

  if client_id == nil or token == nil or type(value) ~= "table" then
    return
  end

  local bucket = ensure_client_bucket(client_id)

  if value.kind == "begin" then
    bucket[token] = true
  elseif value.kind == "end" then
    bucket[token] = nil
  end
end

local function wait_then_open(args)
  if not args.requested then
    snacks_open(args.picker_opts)
    return
  end

  local tracker = tracker_for_clients(args.supported_clients)

  local group = vim.api.nvim_create_augroup("custom_lsp_diag_picker_" .. tostring(vim.loop.hrtime()), { clear = true })

  vim.api.nvim_create_autocmd("LspProgress", {
    group = group,
    callback = function(ev)
      local client_id = ev.data.client_id
      if not tracker.client_set[client_id] then
        return
      end

      local token = progress_token(ev)
      local value = progress_value(ev)
      if token == nil or type(value) ~= "table" then
        return
      end

      if value.kind == "begin" then
        tracker.started[client_id] = tracker.started[client_id] or {}
        tracker.started[client_id][token] = true
      end
    end,
  })

  vim.defer_fn(function()
    if not tracker_has_started(tracker) then
      pcall(vim.api.nvim_del_augroup_by_id, group)
      snacks_open(args.picker_opts)
      return
    end

    local function poll_until_done()
      vim.defer_fn(function()
        if tracker_is_done(tracker) then
          pcall(vim.api.nvim_del_augroup_by_id, group)
          snacks_open(args.picker_opts)
        else
          poll_until_done()
        end
      end, 100)
    end

    poll_until_done()
  end, 100)
end

function M.workspace()
  local bufnr = vim.api.nvim_get_current_buf()
  local bufnrs = { bufnr }
  local requested, clients, supported = request_workspace_diagnostics(bufnrs)

  if not requested then
    notify_no_support(clients, "workspace diagnostics")
  end

  wait_then_open({
    requested = requested,
    supported_clients = supported,
    picker_opts = {
      title = "Workspace Diagnostics",
      filter = { cwd = true },
    },
  })
end

function M.buffer()
  local bufnr = vim.api.nvim_get_current_buf()
  local bufnrs = { bufnr }
  local requested, clients, supported = request_document_diagnostics(bufnrs)

  if not requested then
    notify_no_support(clients, "document diagnostics")
  end

  wait_then_open({
    requested = requested,
    supported_clients = supported,
    picker_opts = {
      title = "Buffer Diagnostics",
      filter = { buf = true },
    },
  })
end

function M.open_files()
  local bufnrs = get_open_file_bufnrs()
  local requested, clients, supported = request_document_diagnostics(bufnrs)

  if not requested then
    notify_no_support(clients, "document diagnostics")
  end

  wait_then_open({
    requested = requested,
    supported_clients = supported,
    picker_opts = {
      title = "Open File Diagnostics",
      filter = {
        filter = open_files_filter(bufnrs),
      },
    },
  })
end

return M
