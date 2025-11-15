local M = {}

-- Helper: Extract repo owner and name from git remote
-- Very light-weight parsing for the common "git@" and "https://" remotes
local function current_repo()
  local remote = (vim.fn.systemlist({ "git", "remote", "get-url", "origin" })[1] or ""):gsub("%.git$", "")
  local owner, repo = remote:match("github%.com[:/](.-)/(.-)$")
  return owner or "", repo or ""
end

-- Helper: Convert ISO timestamp to relative time
local function iso_to_relative(iso)
  local ok, t = pcall(function()
    return vim.fn.strptime("%Y-%m-%dT%H:%M:%SZ", iso)
  end)
  if not ok or not t then
    return "?"
  end
  local delta = os.time() - t
  if delta < 60 then
    return delta .. " s ago"
  elseif delta < 3600 then
    return math.floor(delta / 60) .. " m ago"
  elseif delta < 86400 then
    return math.floor(delta / 3600) .. " h ago"
  else
    return math.floor(delta / 86400) .. " d ago"
  end
end

-- Removed helper functions for fetching extra details - keeping it simple

-- Fetch notifications from GitHub using the gh CLI with full data
local function fetch_notifications()
  local owner, repo = current_repo()
  if owner == "" or repo == "" then
    return {}
  end

  local endpoint = string.format("/repos/%s/%s/notifications", owner, repo)
  local cmd = {
    "gh",
    "api",
    string.format("%s?participating=true&per_page=100&all=true", endpoint),
    "--jq",
    ".[] | @json",
  }

  local json_lines = vim.fn.systemlist(cmd)
  local notes = {}

  for _, line in ipairs(json_lines) do
    local ok, obj = pcall(vim.json.decode, line)
    if ok then
      local subj = obj.subject or {}
      notes[#notes + 1] = {
        -- Core fields
        id = obj.id,
        unread = obj.unread,
        reason = obj.reason, -- e.g. "mention", "author", "subscribed", etc.
        updated_at = obj.updated_at,
        last_read_at = obj.last_read_at,

        -- Repository info
        repo = owner .. "/" .. repo,
        repo_full_name = obj.repository and obj.repository.full_name or (owner .. "/" .. repo),
        repo_private = obj.repository and obj.repository.private or false,

        -- Subject details
        title = subj.title or "",
        type = subj.type or "", -- "PullRequest", "Issue", "Release", etc.
        api_url = subj.url or "",
        comment_url = subj.latest_comment_url or "",

        -- Subscription info
        subscription_url = obj.subscription_url,

        -- Make fuzzy searchable
        text = subj.title or "", -- will be set in formatter

        -- Store full objects for preview
        _raw = obj,
      }
    end
  end
  table.sort(notes, function(a, b)
    return a.updated_at > b.updated_at
  end)
  return notes
end

-- Format notification row for the picker display
---@param item   table
---@param picker table
local function format_notification_row(item, picker)
  local align = require("snacks.picker.util").align
  local ret = {}
  -- if there is a new comment on the PR/issue I have not read, show the type as red
  if item.comment_url ~= "" then
    ret[#ret + 1] = { align(item.type or "", 12), item.unread and "SnacksPickerSelected" or "SnacksIndent" }
  else
    ret[#ret + 1] = { align(item.type or "", 12), item.unread and "SnacksPickerIdx" or "SnacksIndent" }
  end
  ret[#ret + 1] = { align(item.reason or "?", 12), item.unread and "SnacksIndent2" or "SnacksIndent" }
  ret[#ret + 1] = { " " .. iso_to_relative(item.updated_at), item.unread and "SnacksIndent1" or "SnacksIndent" }
  ret[#ret + 1] =
    { " " .. (item.title ~= "" and item.title or "<no title>"), item.unread and "SnacksIndent4" or "SnacksIndent" }
  -- Make fuzzy searchable
  item.text = table.concat(
    vim.tbl_map(function(seg)
      return seg[1]
    end, ret),
    ""
  )

  return ret
end

-- Generate clean preview content for the selected notification
---@param ctx table The picker context with ctx.item and ctx.preview
local function generate_preview(ctx)
  -- Reset the preview
  ctx.preview:reset()

  local item = ctx.item
  if not item then
    ctx.preview:set_lines({ "No notification selected" })
    return
  end

  local lines = {}

  -- Header with notification status
  lines[#lines + 1] = string.format("╭─ %s ─╮", item.unread and "🔴 UNREAD" or "✅ READ")
  lines[#lines + 1] = ""

  -- Title and type
  lines[#lines + 1] = "📋 " .. item.type .. ": " .. item.title
  lines[#lines + 1] = ""
  lines[#lines + 1] = "─────────────────────────────────────"
  lines[#lines + 1] = ""

  -- Core information
  lines[#lines + 1] = "📍 Repository: " .. item.repo_full_name
  if item.repo_private then
    lines[#lines + 1] = "🔒 Private repository"
  end
  lines[#lines + 1] = ""

  -- Notification reason with better descriptions
  local reason_descriptions = {
    assign = "You were assigned to this",
    author = "You created this",
    comment = "You commented on this",
    invitation = "You were invited to contribute",
    manual = "You manually subscribed",
    mention = "You were @mentioned",
    review_requested = "Your review was requested",
    security_alert = "Security vulnerability found",
    state_change = "State was changed",
    subscribed = "You're watching this repository",
    team_mention = "Your team was mentioned",
  }
  local reason_desc = reason_descriptions[item.reason] or item.reason
  lines[#lines + 1] = "🔔 Reason: " .. reason_desc
  lines[#lines + 1] = ""

  -- Timing information
  lines[#lines + 1] = "🕒 Updated: " .. iso_to_relative(item.updated_at)
  if item.last_read_at then
    lines[#lines + 1] = "👁️  Last read: " .. iso_to_relative(item.last_read_at)
  end
  lines[#lines + 1] = ""

  -- URLs
  lines[#lines + 1] = "─────────────────────────────────────"
  lines[#lines + 1] = ""
  if item.comment_url and item.comment_url ~= "" then
    lines[#lines + 1] = "💬 Has new comments"
  end

  -- Raw notification data (for debugging/curiosity)
  if item._raw then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "─────────────────────────────────────"
    lines[#lines + 1] = "📊 Raw Notification Data:"
    lines[#lines + 1] = ""

    -- Show formatted JSON of the raw notification
    local ok, formatted = pcall(vim.json.encode, item._raw)
    if ok then
      -- Pretty print the JSON
      local json_lines = vim.split(formatted, "\n")
      for i, line in ipairs(json_lines) do
        if i <= 30 then -- Limit to first 30 lines
          lines[#lines + 1] = line
        end
      end
      if #json_lines > 30 then
        lines[#lines + 1] = "... (" .. (#json_lines - 30) .. " more lines)"
      end
    end
  end

  ctx.preview:set_lines(lines)
end

-- Helper: Mark a notification as read
local function mark_as_read(item)
  if not item or not item.id then
    return
  end

  local owner, repo = current_repo()
  if owner == "" or repo == "" then
    return
  end

  local endpoint = string.format("/repos/%s/%s/notifications/threads/%s", owner, repo, item.id)
  vim.fn.system({
    "gh",
    "api",
    endpoint,
    "-X",
    "PATCH",
    "-f",
    "read=true",
  })

  -- Update the item to reflect it's been read
  item.unread = false
  vim.notify(string.format("✓ Marked '%s' as read", item.title), vim.log.levels.INFO)
end

-- Main notification picker function
M.picker = function()
  Snacks.picker({
    finder = fetch_notifications,
    format = format_notification_row,
    preview = generate_preview,
    actions = {
      mark_read = function(picker, item)
        if item then
          mark_as_read(item)
          -- Refresh the picker to show updated status
          picker:find()
        end
      end,
      mark_all_read = function(picker)
        local owner, repo = current_repo()
        if owner == "" or repo == "" then
          return
        end

        -- Mark all notifications as read
        vim.fn.system({
          "gh",
          "api",
          string.format("/repos/%s/%s/notifications", owner, repo),
          "-X",
          "PUT",
          "-f",
          "read=true",
        })

        vim.notify("✓ Marked all notifications as read", vim.log.levels.INFO)
        -- Refresh the picker
        picker:find()
      end,
      refresh = function(picker)
        -- Simply refresh the list
        picker:find()
        vim.notify("🔄 Refreshed notifications", vim.log.levels.INFO)
      end,
    },
    confirm = function(picker, item)
      picker:close()
      local url = vim.fn.system({
        "gh",
        "api",
        -- get the comment URL if it exists, otherwise use the API URL
        item.comment_url ~= "" and item.comment_url or item.api_url,
        "--jq",
        ".html_url",
      })
      url = vim.trim(url) -- remove trailing newline
      if url == "" then
        vim.notify("Failed to fetch URL for notification: " .. item.title, vim.log.levels.ERROR)
        return
      end
      vim.ui.open(url)
    end,
    win = {
      input = {
        keys = {
          -- Only in normal mode for input - otherwise can't type these letters!
          ["m"] = { "mark_read", desc = "Mark as read", mode = { "n" } },
          ["M"] = { "mark_all_read", desc = "Mark all as read", mode = { "n" } },
          ["R"] = { "refresh", desc = "Refresh notifications", mode = { "n" } },
        },
      },
      list = {
        keys = {
          ["m"] = { "mark_read", desc = "Mark as read" },
          ["M"] = { "mark_all_read", desc = "Mark all as read" },
          ["R"] = { "refresh", desc = "Refresh notifications" },
        },
      },
      preview = {
        keys = {
          ["m"] = { "mark_read", desc = "Mark as read" },
          ["M"] = { "mark_all_read", desc = "Mark all as read" },
          ["R"] = { "refresh", desc = "Refresh notifications" },
        },
      },
    },
  })
end

return M
