-- A blink.cmp source for a task's due date. On a task's lines, @ and a word
-- that markdown.tasks reads as a date, such as @fri, @tmr or @3d, completes
-- to 📅 and that date, which replaces any date the task had. A bare @ offers
-- today, tomorrow and the seven days after them, and a word such as @t
-- offers the dates of the words it starts.
local tasks = require("markdown.tasks")

---@type string[]
local WORDS = { "today", "tomorrow", "sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday" }

---@class markdown.DueSource : blink.cmp.Source
local source = {}

function source.new()
  return setmetatable({}, { __index = source })
end

function source:get_trigger_characters()
  return { "@" }
end

---@param word string what follows the @
---@return string[] dates YYYY-MM-DD, in order
local function dates_for(word)
  local dates = {}
  if word == "" then
    for days = 0, 8 do
      dates[#dates + 1] = tasks.day(days)
    end
    return dates
  end
  word = word:lower()
  for _, candidate in ipairs({ word, unpack(WORDS) }) do
    local date = vim.startswith(candidate, word) and tasks.due_date(candidate)
    if date and not vim.tbl_contains(dates, date) then
      dates[#dates + 1] = date
    end
  end
  return dates
end

---@param ctx blink.cmp.Context
---@param callback fun(response: blink.cmp.CompletionResponse)
function source:get_completions(ctx, callback)
  local row, col = ctx.cursor[1], ctx.cursor[2]
  local before = ctx.line:sub(1, col)
  local at, word = before:match("()@([%w%-]*)$")
  local items = {}
  -- An @ inside a word, as in an email address, is not a date.
  if at and (at == 1 or before:sub(at - 1, at - 1):match("%s")) and tasks.find(ctx.bufnr, row) then
    local finish = col + #ctx.line:sub(col + 1):match("^[%w%-]*")
    -- A task has one date, so the new one takes the place of any it had.
    local old = tasks.due_range(ctx.bufnr, row)
    local today, tomorrow = tasks.day(0), tasks.day(1)
    for _, date in ipairs(dates_for(word)) do
      items[#items + 1] = {
        label = tasks.label(date),
        labelDetails = { description = date == today and "today" or date == tomorrow and "tomorrow" or nil },
        filterText = "@" .. word,
        sortText = date,
        kind_name = "Date",
        -- LazyVim's kind icons end in a space, so the menu has no gap of its own.
        kind_icon = "📅 ",
        textEdit = {
          newText = "📅 " .. date,
          range = {
            start = { line = row - 1, character = at - 1 },
            ["end"] = { line = row - 1, character = finish },
          },
        },
        additionalTextEdits = old and { { newText = "", range = old } } or nil,
      }
    end
  end
  -- Each new letter can change the date, so blink asks again on every key.
  callback({ items = items, is_incomplete_forward = true, is_incomplete_backward = true })
end

local namespace = vim.api.nvim_create_namespace("markdown.due_source")

---blink.cmp puts the cursor in the wrong column when removing the old date
---joins the line above into the @word's line, so the cursor goes to an
---extmark that follows the end of the @word through both edits.
---@param ctx blink.cmp.Context
---@param item blink.cmp.CompletionItem
function source:execute(ctx, item, callback, default_implementation)
  local finish = item.textEdit.range["end"]
  local mark = vim.api.nvim_buf_set_extmark(ctx.bufnr, namespace, finish.line, finish.character, {})
  default_implementation()
  local row, col = unpack(vim.api.nvim_buf_get_extmark_by_id(ctx.bufnr, namespace, mark, {}))
  vim.api.nvim_buf_del_extmark(ctx.bufnr, namespace, mark)
  vim.api.nvim_win_set_cursor(0, { row + 1, col })
  callback()
end

return source
