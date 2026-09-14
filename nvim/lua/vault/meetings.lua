-- Meeting notes and reciprocal links between vault notes.
--
-- Meetings are running notes in `meetings/`. An occurrence links the meeting
-- note and the relevant daily note in both directions; other note pairs use
-- a small reciprocal `## Links` section.
local notes = require("vault.notes")
local vault = require("vault")

local M = {}

local DAILY_RE = "^daily/(%d%d%d%d%-%d%d%-%d%d)%.md$"
local MEETING_RE = "^meetings/.+%.md$"
local TIME_FORMS = "10:00, 3pm, or leave blank"

---@param token string
---@return string|nil
local function clock(token)
  token = vim.trim(token):lower():gsub("^@", "")
  if token == "" then
    return ""
  end

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

---@param note { relative: string, path: string, title: string }
---@return string|nil
local function daily_date(note)
  return note.relative:match(DAILY_RE)
end

---@param note { relative: string, path: string, title: string }
---@return boolean
local function is_meeting(note)
  return note.relative:match(MEETING_RE) ~= nil
end

---@param relative string
---@return string
local function link_target(relative)
  return (relative:gsub("%.md$", ""))
end

---@param note { relative: string, path: string, title: string }
---@param target { relative: string, path: string, title: string }
---@param at string
---@return nil
local function link_occurrence(note, target, at)
  local date = daily_date(note) or daily_date(target)
  local daily = daily_date(note) and note or target
  local meeting = is_meeting(note) and note or target
  if not date or not daily or not meeting then
    return
  end

  ---@type string
  local daily_link
  daily_link = at == "" and "- [[%s|%s]]" or "- %s [[%s|%s]]"
  if at == "" then
    daily_link = string.format(daily_link, link_target(meeting.relative), meeting.title)
  else
    daily_link = string.format(daily_link, at, link_target(meeting.relative), meeting.title)
  end
  ---@type string
  local meeting_link
  meeting_link = at == "" and "- %s [[%s|%s]]" or "- %s %s [[%s|%s]]"
  if at == "" then
    meeting_link = string.format(meeting_link, date, link_target(daily.relative), date)
  else
    meeting_link = string.format(meeting_link, date, at, link_target(daily.relative), date)
  end

  if not notes.editable(daily.path) or not notes.editable(meeting.path) then
    return
  end
  notes.append_unique(daily.path, daily_link, "## Meetings")
  notes.append_unique(meeting.path, meeting_link, "## Meetings")
  vim.notify(("linked %s and %s"):format(daily.title, meeting.title))
end

---@param note { relative: string, path: string, title: string }
---@param target { relative: string, path: string, title: string }
---@return nil
local function link_notes(note, target)
  if note.path == target.path then
    vim.notify("choose a different note", vim.log.levels.ERROR)
    return
  end

  if (daily_date(note) and is_meeting(target)) or (daily_date(target) and is_meeting(note)) then
    ---@param input string|nil
    vim.ui.input({ prompt = ("Meeting time (%s): "):format(TIME_FORMS) }, function(input)
      if input == nil then
        return
      end
      local at = clock(input)
      if not at then
        vim.notify(("not a meeting time: %s"):format(TIME_FORMS), vim.log.levels.ERROR)
        return
      end
      link_occurrence(note, target, at)
    end)
    return
  end

  local note_link = ("- [[%s|%s]]"):format(link_target(target.relative), target.title)
  local target_link = ("- [[%s|%s]]"):format(link_target(note.relative), note.title)
  if not notes.editable(note.path) or not notes.editable(target.path) then
    return
  end
  notes.append_unique(note.path, note_link, "## Links")
  notes.append_unique(target.path, target_link, "## Links")
  vim.notify(("linked %s and %s"):format(note.title, target.title))
end

---@return nil
function M.search()
  if not vault.require_notes() then
    return
  end
  ---@param selected vault.NoteItem
  notes.pick("meeting", function(selected)
    notes.open_or_create("meeting", selected)
  end)
end

---@return nil
function M.link()
  local current = notes.current()
  if not current then
    return
  end
  ---@param selected vault.NoteItem
  notes.pick_all(function(selected)
    if selected.file and selected.relative then
      link_notes(current, {
        path = selected.file,
        relative = selected.relative,
        title = selected.title,
      })
    end
  end)
end

---@return nil
function M.link_today()
  if not vault.require_notes() then
    return
  end
  local current = notes.current()
  if not current then
    return
  end

  local date = os.date("%Y-%m-%d")
  local relative = "daily/" .. date .. ".md"
  local path = vim.fs.normalize(vault.dir() .. "/" .. relative)
  if current.path == path then
    vim.notify("today's daily note is the current note", vim.log.levels.INFO)
    return
  end

  if vim.fn.filereadable(path) == 0 then
    local daily_dir = vim.fs.normalize(vault.dir() .. "/daily")
    if vim.fn.mkdir(daily_dir, "p") == 0 and vim.fn.isdirectory(daily_dir) == 0 then
      vim.notify(("could not create daily note directory: %s"):format(daily_dir), vim.log.levels.ERROR)
      return
    end
    ---@type any
    local daily = require("obsidian.daily").today()
    if not daily:exists() then
      daily:write()
    end
  end

  if vim.fn.filereadable(path) == 0 then
    vim.notify(("could not create today's daily note: %s"):format(path), vim.log.levels.ERROR)
    return
  end
  link_notes(current, { path = path, relative = relative, title = notes.title(path) })
end

return M
