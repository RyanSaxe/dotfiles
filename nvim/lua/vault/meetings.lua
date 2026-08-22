-- Meeting capture: one prompt, `Name @time`, the same shape as a task.
--
-- A meeting is a heading inside today's daily note rather than a file of its
-- own, so the daily note stays the index of the day. Meetings are prose:
-- Neovim writes them and nothing else reads them, which is exactly why they
-- are not the CLI's business the way tasks are.
local vault = require("vault")
local notes = require("vault.notes")

local M = {}

local TIME_FORMS = "@3pm, @9:30am, or @15:00"

---@param token string
---@return string|nil
local function clock(token)
  token = token:lower()

  local hour, minute, meridiem = token:match("^(%d%d?):(%d%d)([ap]m)$")
  if not hour then
    hour, meridiem = token:match("^(%d%d?)([ap]m)$")
    minute = "00"
  end
  if not hour then
    hour, minute = token:match("^(%d%d?):(%d%d)$")
    meridiem = nil
  end
  if not hour or not minute then
    return nil
  end

  local value = assert(tonumber(hour))
  if meridiem then
    if value < 1 or value > 12 then
      return nil
    end
    if meridiem == "pm" and value < 12 then
      value = value + 12
    elseif meridiem == "am" and value == 12 then
      value = 0
    end
  elseif value > 23 then
    return nil
  end
  if assert(tonumber(minute)) > 59 then
    return nil
  end

  return ("%02d:%s"):format(value, minute)
end

---@param name string
---@return string
local function slugify(name)
  local slug = name:lower()
  slug = slug:gsub("[^%w]+", "-")
  slug = slug:gsub("^%-+", "")
  slug = slug:gsub("%-+$", "")
  return slug
end

-- The heading goes at the end of the note, through the buffer rather than
-- behind it: the daily note is very often already open, and writing to disk
-- under a loaded buffer is how two versions of a day start disagreeing.
---@param at string
---@param slug string
---@param name string
---@return nil
local function append_heading(at, slug, name)
  local buf = vim.api.nvim_get_current_buf()
  local last = vim.api.nvim_buf_line_count(buf)
  local tail = vim.api.nvim_buf_get_lines(buf, last - 1, last, false)[1] or ""

  ---@type string[]
  local block = {}
  if vim.trim(tail) ~= "" then
    block[#block + 1] = ""
  end
  block[#block + 1] = ("## %s [[%s|%s]]"):format(at, slug, name)
  block[#block + 1] = ""

  vim.api.nvim_buf_set_lines(buf, last, last, false, block)
  vim.api.nvim_win_set_cursor(0, { last + #block, 0 })
  vim.cmd.update()
end

---@return nil
function M.capture()
  if not vault.require_notes() then
    return
  end

  ---@param input string|nil
  vim.ui.input({ prompt = "Meeting" }, function(input)
    if not input or vim.trim(input) == "" then
      return
    end

    local name, token = input:match("^(.-)%s+@(%S+)%s*$")
    name = name and vim.trim(name) or ""
    if name == "" or not token then
      vim.notify(("a meeting heading is a start time: write `Name %s`"):format(TIME_FORMS), vim.log.levels.ERROR)
      return
    end

    local at = clock(token)
    if not at then
      vim.notify(("`@%s` is not a start time — use %s"):format(token, TIME_FORMS), vim.log.levels.ERROR)
      return
    end

    local slug = slugify(name)
    if slug == "" then
      vim.notify(("no file name can be made from %q"):format(name), vim.log.levels.ERROR)
      return
    end

    local person = notes.types().person
    if not person then
      vim.notify(
        ("no `person` template under %s — re-run install.sh"):format(vault.templates_dir()),
        vim.log.levels.ERROR
      )
      return
    end

    -- The person note goes through the same type-driven creation as
    -- <leader>on, with the slug as its file name and the typed name as its
    -- title, and it is not opened: the meeting is what was being captured.
    notes.create(person, { id = slug, title = name, open = false })

    ---@type any
    local daily = require("obsidian.daily").today()
    if not daily:exists() then
      daily:write()
    end
    daily:open({ sync = true })
    append_heading(at, slug, name)
  end)
end

return M
