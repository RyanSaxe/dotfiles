local uv = vim.uv or vim.loop

local M = {}

local EXTRA_SESSIONOPTIONS = { "blank", "localoptions", "terminal" }

local function notify_error(message)
  vim.notify(message, vim.log.levels.ERROR, { title = "Restart Here" })
end

local function delete_file(path)
  pcall(vim.fn.delete, path)
end

local function session_dir()
  return vim.fs.joinpath(vim.fn.stdpath("state"), "restart-sessions")
end

local function session_path()
  return vim.fs.joinpath(session_dir(), ("restart-%d-%d.vim"):format(vim.fn.getpid(), uv.hrtime()))
end

local function merged_sessionoptions()
  local merged = {}
  local seen = {}

  for _, option in ipairs(vim.split(vim.o.sessionoptions, ",", { trimempty = true })) do
    if not seen[option] then
      seen[option] = true
      table.insert(merged, option)
    end
  end

  for _, option in ipairs(EXTRA_SESSIONOPTIONS) do
    if not seen[option] then
      seen[option] = true
      table.insert(merged, option)
    end
  end

  return table.concat(merged, ",")
end

local function with_restart_sessionoptions(callback)
  local original = vim.o.sessionoptions
  vim.o.sessionoptions = merged_sessionoptions()

  local ok, result = pcall(callback)
  vim.o.sessionoptions = original

  if not ok then
    error(result)
  end

  return result
end

local function source_session(path)
  vim.cmd("silent source " .. vim.fn.fnameescape(path))
end

local function cleanup_after_restore(path, err)
  vim.schedule(function()
    delete_file(path)

    if err then
      notify_error(("Failed to restore restart session:\n%s"):format(err))
    end
  end)
end

function M.restore(path)
  local ok, err = pcall(function()
    source_session(path)
  end)

  cleanup_after_restore(path, ok and nil or err)
end

function M.restart_here()
  local dir = session_dir()
  if vim.fn.mkdir(dir, "p") == 0 then
    notify_error(("Failed to create restart session directory: %s"):format(dir))
    return
  end

  local path = session_path()
  local ok, err = pcall(function()
    with_restart_sessionoptions(function()
      vim.cmd("mksession! " .. vim.fn.fnameescape(path))
    end)

    -- Delegate modified-buffer prompting to Neovim's built-in confirm flow.
    vim.cmd(("confirm restart lua require('custom.session.restart').restore(%s)"):format(vim.inspect(path)))
  end)

  if ok then
    return
  end

  delete_file(path)
  notify_error(("Restart cancelled or failed:\n%s"):format(err))
end

return M
