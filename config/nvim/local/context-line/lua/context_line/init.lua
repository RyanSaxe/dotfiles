-- Pins the headers of the blocks around the cursor to the top of each
-- window, one row per block, each header collapsed to one line.
local blocks = require("context_line.blocks")
local header = require("context_line.header")
local render = require("context_line.render")

local M = {}

---@class context_line.Config
---@field max_lines integer most rows to pin; the rows never cover the cursor
---@field trim_scope "outer"|"inner" which blocks to drop past `max_lines`
---@field separator string|false a character repeated into a line under the header, or false for none
---@field throttle integer milliseconds between refreshes while events keep coming
---@field zindex integer
local defaults = {
  max_lines = 4,
  trim_scope = "outer",
  separator = false,
  throttle = 50,
  zindex = 20,
}

local config = vim.deepcopy(defaults)

---@param winid integer
---@return context_line.Row[]
local function rows_for(winid)
  local bufnr = vim.api.nvim_win_get_buf(winid)
  if vim.api.nvim_win_get_config(winid).relative ~= "" or vim.bo[bufnr].filetype == "" then
    return {}
  end
  local parser = vim.treesitter.get_parser(bufnr, nil, { error = false })
  if not parser then
    return {}
  end
  local width = vim.api.nvim_win_get_width(winid) - vim.fn.getwininfo(winid)[1].textoff
  local rows = {} ---@type context_line.Row[]
  for _, block in ipairs(blocks.find(winid, parser, config)) do
    local text, marks = header.line(parser, bufnr, block, width)
    rows[#rows + 1] = { lnum = block.start_row + 1, text = text, marks = marks }
  end
  return rows
end

local function refresh()
  if vim.fn.getcmdtype() ~= "" then
    return
  end
  local tabpage = vim.api.nvim_get_current_tabpage()
  local shown = {} ---@type table<integer, true>
  for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
    local rows = rows_for(winid)
    if #rows > 0 then
      render.show(winid, rows, config)
      shown[winid] = true
    end
  end
  render.close_others(shown, tabpage)
end

local timer = assert(vim.uv.new_timer())
local requested_while_waiting = false

--- Refreshes on the next tick, then at most once per `config.throttle`
--- milliseconds, with a last refresh after the events stop.
local function request_refresh()
  if timer:is_active() then
    requested_while_waiting = true
    return
  end
  vim.schedule(refresh)
  timer:start(config.throttle, 0, function()
    if requested_while_waiting then
      requested_while_waiting = false
      vim.schedule(request_refresh)
    end
  end)
end

---@param opts? context_line.Config
function M.setup(opts)
  config = vim.tbl_deep_extend("force", defaults, opts or {})
  -- This plugin replaces nvim-treesitter-context's window and keeps only its
  -- queries and highlight groups.
  require("treesitter-context").setup({ enable = false })

  local group = vim.api.nvim_create_augroup("context_line", {})
  vim.api.nvim_create_autocmd({
    "BufEnter",
    "CursorMoved",
    "CursorMovedI",
    "InsertLeave",
    "TextChanged",
    "TextChangedI",
    "WinResized",
    "WinScrolled",
  }, { group = group, callback = request_refresh })
  -- Diagnostics and the language server's token colors arrive a moment
  -- after an edit, so these recolor the header once they do.
  vim.api.nvim_create_autocmd("DiagnosticChanged", { group = group, callback = request_refresh })
  vim.api.nvim_create_autocmd("LspRequest", {
    group = group,
    callback = function(args)
      local request = args.data.request
      if request.type == "complete" and request.method:find("^textDocument/semanticTokens") then
        request_refresh()
      end
    end,
  })
  -- The options that change the gutter's width or its line numbers.
  vim.api.nvim_create_autocmd("OptionSet", {
    group = group,
    pattern = { "number", "relativenumber", "numberwidth", "signcolumn", "foldcolumn", "statuscolumn" },
    callback = request_refresh,
  })
  vim.api.nvim_create_autocmd("WinClosed", {
    group = group,
    callback = function(args)
      local winid = tonumber(args.match) --[[@as integer]]
      vim.schedule(function()
        render.close(winid)
      end)
    end,
  })
  request_refresh()
end

return M
