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

-- Helper: Extract PR/Issue/Release number from API URL
local function extract_number_from_url(api_url)
  if not api_url then return nil end
  -- Try to extract number from various GitHub API URL patterns
  return api_url:match("/pulls/(%d+)$") or
         api_url:match("/issues/(%d+)$") or
         api_url:match("/releases/(%d+)$")
end

-- Helper: Check if notification has new activity since last read
local function has_new_activity(item)
  -- If never read, it's all new
  if not item.last_read_at or item.last_read_at == vim.NIL then
    return true
  end

  -- If no updated_at, assume no new activity
  if not item.updated_at or item.updated_at == vim.NIL then
    return false
  end

  -- ISO 8601 timestamps can be compared as strings (they're lexicographically sortable)
  -- Use tostring to ensure both values are strings (in case one is userdata)
  return tostring(item.updated_at) > tostring(item.last_read_at)
end

-- Helper: Check if notification has new activity AND comments
local function has_new_discussion(item)
  return has_new_activity(item) and
         item.latest_comment_url and
         item.latest_comment_url ~= ""
end

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
        latest_comment_url = subj.latest_comment_url or "",

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

  -- Build type display with PR/Issue number if available
  local type_display = item.type or ""
  local number = extract_number_from_url(item.api_url)
  if number then
    if item.type == "PullRequest" then
      type_display = "PR #" .. number
    elseif item.type == "Issue" then
      type_display = "Issue #" .. number
    else
      type_display = item.type .. " #" .. number
    end
  end

  -- Check for new discussion activity (new activity + has comments)
  local new_discussion = has_new_discussion(item)
  local new_activity = has_new_activity(item)

  -- Choose highlight based on activity status
  local type_highlight
  if new_discussion then
    -- BRIGHT highlight for items with NEW activity AND comments (most important!)
    type_highlight = item.unread and "DiagnosticError" or "DiagnosticWarn"
  elseif new_activity then
    -- Medium highlight for new activity without comments
    type_highlight = item.unread and "SnacksPickerSelected" or "SnacksPickerIdx"
  else
    -- Normal highlight for old items
    type_highlight = item.unread and "SnacksPickerIdx" or "SnacksIndent"
  end

  -- Add type with appropriate highlighting
  ret[#ret + 1] = { align(type_display, 12), type_highlight }

  -- Add new activity indicator
  local activity_indicator = ""
  if new_discussion then
    activity_indicator = "🔥 " -- Hot discussion!
  elseif new_activity then
    activity_indicator = "🆕 " -- New activity
  else
    activity_indicator = "   " -- Spacing for alignment
  end
  ret[#ret + 1] = { activity_indicator, new_discussion and "DiagnosticError" or "SnacksIndent" }

  -- Reason
  ret[#ret + 1] = { align(item.reason or "?", 12), item.unread and "SnacksIndent2" or "SnacksIndent" }

  -- Time
  ret[#ret + 1] = { " " .. iso_to_relative(item.updated_at), item.unread and "SnacksIndent1" or "SnacksIndent" }

  -- Title
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

-- Generate clean markdown preview for the selected notification
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

  -- Header with notification status and activity indicator
  local status = item.unread and "🔴 **UNREAD**" or "✅ **READ**"
  local activity_badge = ""
  if has_new_discussion(item) then
    activity_badge = " 🔥 **HOT DISCUSSION**"
  elseif has_new_activity(item) then
    activity_badge = " 🆕 **NEW ACTIVITY**"
  end
  lines[#lines + 1] = "# " .. status .. activity_badge
  lines[#lines + 1] = ""

  -- Title and type with PR/Issue number
  local number = extract_number_from_url(item.api_url)
  local type_display = item.type
  if number then
    if item.type == "PullRequest" then
      type_display = "PR #" .. number
    elseif item.type == "Issue" then
      type_display = "Issue #" .. number
    else
      type_display = item.type .. " #" .. number
    end
  end
  lines[#lines + 1] = "## " .. type_display .. ": " .. item.title
  lines[#lines + 1] = ""
  lines[#lines + 1] = "---"
  lines[#lines + 1] = ""

  -- Core information as a table
  lines[#lines + 1] = "### 📋 Notification Details"
  lines[#lines + 1] = ""
  lines[#lines + 1] = "| Field | Value |"
  lines[#lines + 1] = "|-------|-------|"
  lines[#lines + 1] = "| **Repository** | `" .. item.repo_full_name .. "` |"

  if item.repo_private then
    lines[#lines + 1] = "| **Visibility** | 🔒 Private |"
  else
    lines[#lines + 1] = "| **Visibility** | 🌍 Public |"
  end

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
  lines[#lines + 1] = "| **Reason** | " .. reason_desc .. " |"
  lines[#lines + 1] = "| **Updated** | " .. iso_to_relative(item.updated_at) .. " |"

  if item.last_read_at then
    lines[#lines + 1] = "| **Last Read** | " .. iso_to_relative(item.last_read_at) .. " |"
  end

  -- Show activity status
  if has_new_discussion(item) then
    lines[#lines + 1] = "| **Activity Status** | 🔥 New discussion activity! |"
  elseif has_new_activity(item) then
    lines[#lines + 1] = "| **Activity Status** | 🆕 Updated since last read |"
  end

  if item.latest_comment_url and item.latest_comment_url ~= "" then
    lines[#lines + 1] = "| **Comments** | 💬 Has comments |"
  end

  lines[#lines + 1] = ""

  -- Raw notification data as a nice table
  if item._raw then
    lines[#lines + 1] = "---"
    lines[#lines + 1] = ""
    lines[#lines + 1] = "### 📊 Full Notification Data"
    lines[#lines + 1] = ""
    lines[#lines + 1] = "| Property | Value |"
    lines[#lines + 1] = "|----------|-------|"

    -- Helper function to safely get string value
    local function safe_tostring(val)
      if type(val) == "string" then
        return val:gsub("|", "\\|") -- Escape pipes for markdown tables
      elseif type(val) == "boolean" then
        return val and "true" or "false"
      elseif type(val) == "number" then
        return tostring(val)
      elseif val == nil then
        return "null"
      elseif type(val) == "table" then
        -- For tables, just show the type/count
        if vim.tbl_islist(val) then
          return "Array[" .. #val .. "]"
        else
          local count = 0
          for _ in pairs(val) do count = count + 1 end
          return "Object{" .. count .. "}"
        end
      else
        return type(val)
      end
    end

    -- Add main properties
    if item._raw.id then
      lines[#lines + 1] = "| **ID** | `" .. safe_tostring(item._raw.id) .. "` |"
    end
    if item._raw.unread ~= nil then
      lines[#lines + 1] = "| **Unread** | " .. safe_tostring(item._raw.unread) .. " |"
    end
    if item._raw.reason then
      lines[#lines + 1] = "| **Reason** | " .. safe_tostring(item._raw.reason) .. " |"
    end
    if item._raw.updated_at then
      lines[#lines + 1] = "| **Updated At** | `" .. safe_tostring(item._raw.updated_at) .. "` |"
    end
    if item._raw.last_read_at then
      lines[#lines + 1] = "| **Last Read At** | `" .. safe_tostring(item._raw.last_read_at) .. "` |"
    end

    -- Add subject properties
    if item._raw.subject then
      lines[#lines + 1] = "| **Subject Type** | " .. safe_tostring(item._raw.subject.type) .. " |"
      lines[#lines + 1] = "| **Subject Title** | " .. safe_tostring(item._raw.subject.title) .. " |"
      if item._raw.subject.url then
        lines[#lines + 1] = "| **API URL** | `" .. safe_tostring(item._raw.subject.url):sub(1, 50) .. "...` |"
      end
      if item._raw.subject.latest_comment_url then
        lines[#lines + 1] = "| **Latest Comment URL** | `...` |"
      end
    end

    -- Add repository info
    if item._raw.repository then
      lines[#lines + 1] = "| **Repository Name** | " .. safe_tostring(item._raw.repository.name) .. " |"
      lines[#lines + 1] = "| **Repository Owner** | " .. safe_tostring(item._raw.repository.owner and item._raw.repository.owner.login) .. " |"
    end
  end

  ctx.preview:set_lines(lines)
  -- Enable markdown rendering for nice table display
  ctx.preview:highlight({ ft = "markdown" })
end

-- Helper: Mark a notification as read
local function mark_as_read(item)
  if not item or not item.id then
    return
  end

  -- Use the global notifications endpoint (not repository-scoped)
  local endpoint = string.format("/notifications/threads/%s", item.id)
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
    layout = "custom_horizontal", -- Use the custom horizontal layout for better preview display
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
      -- First, mark the notification as read since we're opening it
      mark_as_read(item)

      -- Close the picker
      picker:close()

      -- Extract PR/Issue number if available
      local number = extract_number_from_url(item.api_url)

      -- Smart routing based on notification type
      if item.type == "PullRequest" and number then
        -- Open native PR viewer in Neovim
        vim.notify("📋 Opening PR #" .. number .. " in Neovim", vim.log.levels.INFO)
        Snacks.picker.gh_pr({ search = "#" .. number })

      elseif item.type == "Issue" and number then
        -- Open native Issue viewer in Neovim
        vim.notify("📋 Opening Issue #" .. number .. " in Neovim", vim.log.levels.INFO)
        Snacks.picker.gh_issue({ search = "#" .. number })

      else
        -- For other types (Release, Commit, Discussion), open in browser
        -- TODO: Implement native viewers for:
        --   - Releases (gh_release picker)
        --   - Commits (gh_commit picker)
        --   - Discussions (gh_discussion picker)
        --   These would need custom implementation with Snacks.picker

        local url = vim.fn.system({
          "gh",
          "api",
          -- get the latest comment URL if it exists, otherwise use the API URL
          (item.latest_comment_url and item.latest_comment_url ~= "" and item.latest_comment_url) or item.api_url,
          "--jq",
          ".html_url",
        })
        url = vim.trim(url) -- remove trailing newline
        if url == "" then
          vim.notify("Failed to fetch URL for notification: " .. item.title, vim.log.levels.ERROR)
          return
        end

        -- Notify about browser opening with type info
        local type_msg = item.type or "notification"
        vim.notify("🌐 Opening " .. type_msg .. " in browser (no native viewer yet)", vim.log.levels.INFO)
        vim.ui.open(url)
      end
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
