-- GitHub Comment Thread Picker
--
-- A snacks picker that shows GitHub comment threads requiring attention.
-- Bypasses the broken notification API (where `reason` reflects relationship,
-- not what happened) by directly querying thread state via GraphQL.
--
-- Categories:
--   PENDING (yellow)        - I'm in this thread AND I have the last word -> waiting on them
--   NEEDS_ATTENTION (red)   - I'm in this thread AND someone else has the last word -> needs my response
--   MY_PR (orange)          - Thread on MY PR/Issue where I don't have last word -> needs my response

local M = {}

local git_utils = require("custom.git.utils")

-------------------------------------------------------------------------------
-- Configuration
-------------------------------------------------------------------------------

-- API limits following GitHub's constraints:
-- - search(first:) max 100 (GitHub hard limit)
-- - reviewThreads(last:) 50 to get most recent threads
-- - thread comments(first:) 20 for full context
-- - flat comments(last:) 100 (cheap on node budget)
local CONFIG = {
  search_limit = 100,
  review_threads_limit = 50,
  thread_comments_limit = 20,
  flat_comments_limit = 100,
}

-------------------------------------------------------------------------------
-- State Management
-------------------------------------------------------------------------------

-- Module state persists across picker opens (until Neovim restart)
local state = {
  items = {}, -- All parsed thread items
  show_resolved = false, -- Toggle: false = unresolved, true = resolved
  show_hidden = false, -- Toggle: false = active threads, true = hidden threads
  hidden_threads = {}, -- comment_url -> hide_timestamp (unix time)
  current_repo = nil, -- Detected from git remote (cached)
  username = nil, -- GitHub username (cached)
}

-------------------------------------------------------------------------------
-- Hidden Thread Persistence
-------------------------------------------------------------------------------

-- Path for storing hidden thread state
local function get_hidden_threads_path()
  local data_dir = vim.fn.stdpath("data") .. "/snacks"
  vim.fn.mkdir(data_dir, "p")
  return data_dir .. "/hidden_threads.json"
end

-- Load hidden threads from disk
local function load_hidden_threads()
  local filepath = get_hidden_threads_path()
  local f = io.open(filepath, "r")
  if f then
    local content = f:read("*a")
    f:close()
    local ok, data = pcall(vim.json.decode, content)
    if ok and data then
      state.hidden_threads = data
    end
  end
end

-- Save hidden threads to disk
local function save_hidden_threads()
  local filepath = get_hidden_threads_path()
  local f = io.open(filepath, "w")
  if f then
    f:write(vim.json.encode(state.hidden_threads))
    f:close()
  end
end

-- Register autocommand to save on exit
vim.api.nvim_create_autocmd("ExitPre", {
  group = vim.api.nvim_create_augroup("review_threads_persist", { clear = true }),
  callback = save_hidden_threads,
})

-- Load hidden threads on module init
load_hidden_threads()

-------------------------------------------------------------------------------
-- Helper Functions
-------------------------------------------------------------------------------

-- Get GitHub username (cached)
local function get_username()
  if state.username and state.username ~= "" then
    return state.username
  end
  state.username = git_utils.get_username()
  return state.username
end

-- Get current repo from git remote (cached per session)
-- Returns "owner/repo" or nil if not in a git repo
local function get_current_repo()
  if state.current_repo then
    return state.current_repo
  end
  local remote = (vim.fn.systemlist({ "git", "remote", "get-url", "origin" })[1] or ""):gsub("%.git$", "")
  local owner, repo = remote:match("github%.com[:/](.-)/(.-)$")
  if owner and repo then
    state.current_repo = owner .. "/" .. repo
  end
  return state.current_repo
end

-- Convert ISO 8601 timestamp to relative time string (e.g., "2h ago")
-- GitHub timestamps are UTC, so we need to handle timezone conversion properly
local function iso_to_relative(iso)
  if not iso or iso == "" then
    return "?"
  end
  -- Parse ISO 8601 format: "2024-01-15T10:30:45Z"
  local year, month, day, hour, min, sec = iso:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
  if not year then
    return "?"
  end

  -- os.time() interprets the table as local time, but our input is UTC
  -- Calculate timezone offset to correct for this
  local now = os.time()
  local now_utc_table = os.date("!*t", now) --[[@as osdateparam]]
  now_utc_table.isdst = false
  local tz_offset = now - os.time(now_utc_table)

  -- Parse the UTC timestamp (os.time interprets as local, so we correct with tz_offset)
  -- tonumber() returns number|nil, but we've validated the pattern match above
  ---@diagnostic disable: assign-type-mismatch
  local t = os.time({
    year = tonumber(year),
    month = tonumber(month),
    day = tonumber(day),
    hour = tonumber(hour),
    min = tonumber(min),
    sec = tonumber(sec),
  }) + tz_offset
  ---@diagnostic enable: assign-type-mismatch

  local delta = now - t
  if delta < 0 then
    return "now" -- Handle edge case of slight clock skew
  elseif delta < 60 then
    return delta .. "s"
  elseif delta < 3600 then
    return math.floor(delta / 60) .. "m"
  elseif delta < 86400 then
    return math.floor(delta / 3600) .. "h"
  else
    return math.floor(delta / 86400) .. "d"
  end
end

-- Truncate string to max length with ellipsis
local function truncate(str, max_len)
  if not str then
    return ""
  end
  -- Replace newlines with spaces for single-line display
  str = str:gsub("\n", " "):gsub("%s+", " ")
  if #str <= max_len then
    return str
  end
  return str:sub(1, max_len - 1) .. "…"
end

-- Convert ISO 8601 timestamp to Unix timestamp
-- GitHub timestamps are UTC, so we handle timezone conversion properly
local function iso_to_unix(iso)
  if not iso or iso == "" then
    return nil
  end
  -- Parse ISO 8601 format: "2024-01-15T10:30:45Z"
  local year, month, day, hour, min, sec = iso:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
  if not year then
    return nil
  end

  -- os.time() interprets the table as local time, but our input is UTC
  -- Calculate timezone offset to correct for this
  local now = os.time()
  local now_utc_table = os.date("!*t", now) --[[@as osdateparam]]
  now_utc_table.isdst = false
  local tz_offset = now - os.time(now_utc_table)

  -- Parse the UTC timestamp (os.time interprets as local, so we correct with tz_offset)
  -- tonumber() returns number|nil, but we've validated the pattern match above
  ---@diagnostic disable: assign-type-mismatch
  return os.time({
    year = tonumber(year),
    month = tonumber(month),
    day = tonumber(day),
    hour = tonumber(hour),
    min = tonumber(min),
    sec = tonumber(sec),
  }) + tz_offset
  ---@diagnostic enable: assign-type-mismatch
end

-- Filter items by hidden state
-- @param items table - Array of picker items
-- @param show_hidden boolean - Whether to show hidden (true) or active (false)
-- @return table - Filtered items
local function filter_by_hidden(items, show_hidden)
  return vim.tbl_filter(function(item)
    local is_hidden = state.hidden_threads[item.comment_url] ~= nil
    -- Check for new activity on hidden items
    if is_hidden then
      local comment_time = iso_to_unix(item.comment_created_at)
      local hide_timestamp = state.hidden_threads[item.comment_url]
      if comment_time and hide_timestamp and comment_time > hide_timestamp then
        -- Auto-unhide due to new activity
        state.hidden_threads[item.comment_url] = nil
        is_hidden = false
      end
    end

    if show_hidden then
      return is_hidden
    else
      return not is_hidden
    end
  end, items)
end

-------------------------------------------------------------------------------
-- GraphQL Query
-------------------------------------------------------------------------------

-- Build the GraphQL query with 6 search aliases:
-- commentedPRs, mentionedPRs, myPRs, commentedIssues, mentionedIssues, myIssues
--
-- Important: Use `last:` not `first:` for reviewThreads to get most recent threads
local function build_graphql_query()
  local limits = CONFIG
  return string.format(
    [[
{
  commentedPRs: search(query: "is:open is:pr commenter:@me -author:@me", type: ISSUE, first: %d) {
    nodes {
      ... on PullRequest {
        number
        title
        url
        author { login }
        repository { nameWithOwner }
        reviewThreads(last: %d) {
          nodes {
            id
            isResolved
            comments(first: %d) {
              nodes {
                author { login }
                body
                createdAt
                url
                databaseId
              }
            }
          }
        }
        comments(last: %d) {
          nodes {
            author { login }
            body
            createdAt
            url
            databaseId
          }
        }
      }
    }
  }

  mentionedPRs: search(query: "is:open is:pr mentions:@me -author:@me -commenter:@me", type: ISSUE, first: %d) {
    nodes {
      ... on PullRequest {
        number
        title
        url
        author { login }
        repository { nameWithOwner }
        reviewThreads(last: %d) {
          nodes {
            id
            isResolved
            comments(first: %d) {
              nodes {
                author { login }
                body
                createdAt
                url
                databaseId
              }
            }
          }
        }
        comments(last: %d) {
          nodes {
            author { login }
            body
            createdAt
            url
            databaseId
          }
        }
      }
    }
  }

  myPRs: search(query: "is:open is:pr author:@me", type: ISSUE, first: %d) {
    nodes {
      ... on PullRequest {
        number
        title
        url
        repository { nameWithOwner }
        reviewThreads(last: %d) {
          nodes {
            id
            isResolved
            comments(first: %d) {
              nodes {
                author { login }
                body
                createdAt
                url
                databaseId
              }
            }
          }
        }
        comments(last: %d) {
          nodes {
            author { login }
            body
            createdAt
            url
            databaseId
          }
        }
      }
    }
  }

  commentedIssues: search(query: "is:open is:issue commenter:@me -author:@me", type: ISSUE, first: %d) {
    nodes {
      ... on Issue {
        number
        title
        url
        author { login }
        repository { nameWithOwner }
        comments(last: %d) {
          nodes {
            author { login }
            body
            createdAt
            url
            databaseId
          }
        }
      }
    }
  }

  mentionedIssues: search(query: "is:open is:issue mentions:@me -author:@me -commenter:@me", type: ISSUE, first: %d) {
    nodes {
      ... on Issue {
        number
        title
        url
        author { login }
        repository { nameWithOwner }
        comments(last: %d) {
          nodes {
            author { login }
            body
            createdAt
            url
            databaseId
          }
        }
      }
    }
  }

  myIssues: search(query: "is:open is:issue author:@me", type: ISSUE, first: %d) {
    nodes {
      ... on Issue {
        number
        title
        url
        repository { nameWithOwner }
        comments(last: %d) {
          nodes {
            author { login }
            body
            createdAt
            url
            databaseId
          }
        }
      }
    }
  }
}
]],
    -- commentedPRs
    limits.search_limit,
    limits.review_threads_limit,
    limits.thread_comments_limit,
    limits.flat_comments_limit,
    -- mentionedPRs
    limits.search_limit,
    limits.review_threads_limit,
    limits.thread_comments_limit,
    limits.flat_comments_limit,
    -- myPRs
    limits.search_limit,
    limits.review_threads_limit,
    limits.thread_comments_limit,
    limits.flat_comments_limit,
    -- commentedIssues
    limits.search_limit,
    limits.flat_comments_limit,
    -- mentionedIssues
    limits.search_limit,
    limits.flat_comments_limit,
    -- myIssues
    limits.search_limit,
    limits.flat_comments_limit
  )
end

-------------------------------------------------------------------------------
-- Thread Classification Logic
-------------------------------------------------------------------------------

-- Check if user is participating in a thread (commented OR @mentioned)
-- @param comments table - Array of comment objects with author.login and body
-- @param my_username string - Current user's GitHub username
-- @return boolean
local function is_participating(comments, my_username)
  if not comments or #comments == 0 then
    return false
  end

  for _, comment in ipairs(comments) do
    -- I commented in this thread
    if comment.author and comment.author.login == my_username then
      return true
    end

    -- I was @mentioned in the comment body
    if comment.body then
      local mention_pattern = "@" .. my_username
      -- Match @username followed by whitespace, punctuation, or end of string
      if comment.body:find(mention_pattern .. "[%s%p]") or comment.body:find(mention_pattern .. "$") then
        return true
      end
    end
  end

  return false
end

-- Classify a thread into one of: "pending", "needs_attention", "my_pr", or nil (skip)
--
-- Classification rules:
--   - PENDING: I'm in this thread AND I have the last word -> waiting on them
--   - NEEDS_ATTENTION: I'm in this thread AND someone else has the last word -> needs my response
--   - MY_PR: Thread on MY PR/Issue where I don't have last word -> needs my response
--
-- @param comments table - Array of comments in the thread
-- @param my_username string - Current user's GitHub username
-- @param _item_author string|nil - Author of the PR/Issue (unused, kept for API consistency)
-- @param is_my_item boolean - Whether this is my own PR/Issue
-- @return string|nil - Thread type or nil to skip
local function classify_thread(comments, my_username, _item_author, is_my_item)
  if not comments or #comments == 0 then
    return nil
  end

  local participating = is_participating(comments, my_username)

  -- For my own PRs/Issues, I care about all threads even if I haven't participated yet
  if not participating and not is_my_item then
    return nil -- Not my thread, skip
  end

  local last_comment = comments[#comments]
  if not last_comment or not last_comment.author then
    return nil
  end

  local i_have_last_word = (last_comment.author.login == my_username)

  if is_my_item then
    -- It's my PR/Issue
    if i_have_last_word then
      return nil -- I responded, nothing to do
    else
      return "my_pr" -- Someone commented, need to respond
    end
  else
    -- Someone else's PR/Issue
    if i_have_last_word then
      return "pending" -- Waiting on them
    else
      return "needs_attention" -- They replied, need to respond
    end
  end
end

-------------------------------------------------------------------------------
-- Response Parsing
-------------------------------------------------------------------------------

-- Parse a single PR's review threads into picker items
-- @param pr table - PR node from GraphQL response
-- @param my_username string - Current user's GitHub username
-- @param is_my_pr boolean - Whether this is my own PR
-- @return table - Array of picker items
local function parse_pr_review_threads(pr, my_username, is_my_pr)
  local items = {}

  if not pr.reviewThreads or not pr.reviewThreads.nodes then
    return items
  end

  local repo = pr.repository and pr.repository.nameWithOwner or ""
  local pr_author = pr.author and pr.author.login or ""

  for _, thread in ipairs(pr.reviewThreads.nodes) do
    local comments = thread.comments and thread.comments.nodes or {}
    local thread_type = classify_thread(comments, my_username, pr_author, is_my_pr)

    if thread_type then
      local last_comment = comments[#comments] or {}

      items[#items + 1] = {
        -- Classification
        type = thread_type,
        kind = "pr",
        is_resolved = thread.isResolved or false,

        -- PR/Issue info
        repo = repo,
        number = pr.number,
        title = pr.title or "",
        pr_url = pr.url or "",

        -- Thread-specific (for PR review threads)
        thread_id = thread.id, -- Node ID for resolve/unresolve mutations

        -- Last comment details (what triggered this item)
        comment_body = last_comment.body or "",
        comment_author = last_comment.author and last_comment.author.login or "",
        comment_url = last_comment.url or "",
        comment_created_at = last_comment.createdAt or "",
        comment_database_id = last_comment.databaseId, -- For reply API

        -- Full thread context for preview
        thread_comments = comments,

        -- Fuzzy search text (set by formatter)
        text = "",
      }
    end
  end

  return items
end

-- Parse PR flat comments (general conversation tab) into a single "thread"
-- These don't have thread IDs, so they're treated as a conversation
-- @param pr table - PR node from GraphQL response
-- @param my_username string - Current user's GitHub username
-- @param is_my_pr boolean - Whether this is my own PR
-- @return table|nil - Single picker item or nil
local function parse_pr_flat_comments(pr, my_username, is_my_pr)
  if not pr.comments or not pr.comments.nodes or #pr.comments.nodes == 0 then
    return nil
  end

  local comments = pr.comments.nodes
  local repo = pr.repository and pr.repository.nameWithOwner or ""
  local pr_author = pr.author and pr.author.login or ""

  local thread_type = classify_thread(comments, my_username, pr_author, is_my_pr)
  if not thread_type then
    return nil
  end

  local last_comment = comments[#comments] or {}

  return {
    type = thread_type,
    kind = "pr",
    is_resolved = false, -- Flat comments can't be resolved

    repo = repo,
    number = pr.number,
    title = pr.title or "",
    pr_url = pr.url or "",

    thread_id = nil, -- No thread ID for flat comments

    comment_body = last_comment.body or "",
    comment_author = last_comment.author and last_comment.author.login or "",
    comment_url = last_comment.url or "",
    comment_created_at = last_comment.createdAt or "",
    comment_database_id = last_comment.databaseId,

    thread_comments = comments,
    text = "",
  }
end

-- Parse Issue comments into a single "thread" per issue
-- @param issue table - Issue node from GraphQL response
-- @param my_username string - Current user's GitHub username
-- @param is_my_issue boolean - Whether this is my own issue
-- @return table|nil - Single picker item or nil
local function parse_issue_comments(issue, my_username, is_my_issue)
  if not issue.comments or not issue.comments.nodes or #issue.comments.nodes == 0 then
    return nil
  end

  local comments = issue.comments.nodes
  local repo = issue.repository and issue.repository.nameWithOwner or ""
  local issue_author = issue.author and issue.author.login or ""

  local thread_type = classify_thread(comments, my_username, issue_author, is_my_issue)
  if not thread_type then
    return nil
  end

  local last_comment = comments[#comments] or {}

  return {
    type = thread_type,
    kind = "issue",
    is_resolved = false, -- Issues don't have resolvable threads

    repo = repo,
    number = issue.number,
    title = issue.title or "",
    pr_url = issue.url or "", -- Using pr_url field for consistency

    thread_id = nil,

    comment_body = last_comment.body or "",
    comment_author = last_comment.author and last_comment.author.login or "",
    comment_url = last_comment.url or "",
    comment_created_at = last_comment.createdAt or "",
    comment_database_id = last_comment.databaseId,

    thread_comments = comments,
    text = "",
  }
end

-- Parse entire GraphQL response into picker items
-- @param data table - The `data` field from GraphQL response
-- @param my_username string - Current user's GitHub username
-- @return table - Array of all picker items
local function parse_graphql_response(data, my_username)
  local items = {}

  -- Helper to safely iterate search nodes
  local function process_nodes(search_result, processor)
    if not search_result or not search_result.nodes then
      return
    end
    for _, node in ipairs(search_result.nodes) do
      if node and node.number then -- Ensure it's a valid PR/Issue
        local result = processor(node)
        if result then
          if type(result) == "table" and result.type then
            -- Single item
            items[#items + 1] = result
          else
            -- Array of items
            for _, item in ipairs(result) do
              items[#items + 1] = item
            end
          end
        end
      end
    end
  end

  -- Process PRs I've commented on (not mine)
  process_nodes(data.commentedPRs, function(pr)
    local review_items = parse_pr_review_threads(pr, my_username, false)
    local flat_item = parse_pr_flat_comments(pr, my_username, false)
    if flat_item then
      review_items[#review_items + 1] = flat_item
    end
    return review_items
  end)

  -- Process PRs where I'm mentioned (not mine, not already commented)
  process_nodes(data.mentionedPRs, function(pr)
    local review_items = parse_pr_review_threads(pr, my_username, false)
    local flat_item = parse_pr_flat_comments(pr, my_username, false)
    if flat_item then
      review_items[#review_items + 1] = flat_item
    end
    return review_items
  end)

  -- Process my PRs
  process_nodes(data.myPRs, function(pr)
    local review_items = parse_pr_review_threads(pr, my_username, true)
    local flat_item = parse_pr_flat_comments(pr, my_username, true)
    if flat_item then
      review_items[#review_items + 1] = flat_item
    end
    return review_items
  end)

  -- Process Issues I've commented on
  process_nodes(data.commentedIssues, function(issue)
    return parse_issue_comments(issue, my_username, false)
  end)

  -- Process Issues where I'm mentioned
  process_nodes(data.mentionedIssues, function(issue)
    return parse_issue_comments(issue, my_username, false)
  end)

  -- Process my Issues
  process_nodes(data.myIssues, function(issue)
    return parse_issue_comments(issue, my_username, true)
  end)

  return items
end

-------------------------------------------------------------------------------
-- Filtering and Sorting
-------------------------------------------------------------------------------

-- Filter items by resolved state
-- @param items table - Array of picker items
-- @param show_resolved boolean - Whether to show resolved (true) or unresolved (false)
-- @return table - Filtered items
local function filter_by_resolved(items, show_resolved)
  return vim.tbl_filter(function(item)
    if show_resolved then
      return item.is_resolved
    else
      return not item.is_resolved
    end
  end, items)
end

-- Apply all filters in order: resolved -> hidden
-- @param items table - Array of all items
-- @return table - Filtered items based on current state
local function apply_filters(items)
  local filtered = filter_by_resolved(items, state.show_resolved)
  filtered = filter_by_hidden(filtered, state.show_hidden)
  return filtered
end

-- Sort items: current repo first, then by type priority, then by recency
-- @param items table - Array of picker items
-- @return table - Sorted items (in place)
local function sort_items(items)
  local current_repo = get_current_repo()
  local type_priority = { needs_attention = 1, my_pr = 2, pending = 3 }

  table.sort(items, function(a, b)
    local a_is_current = a.repo == current_repo
    local b_is_current = b.repo == current_repo

    -- Current repo items first
    if a_is_current ~= b_is_current then
      return a_is_current
    end

    -- Within same repo group, sort by type priority
    local a_priority = type_priority[a.type] or 99
    local b_priority = type_priority[b.type] or 99
    if a_priority ~= b_priority then
      return a_priority < b_priority
    end

    -- Finally by recency (most recent first)
    return (a.comment_created_at or "") > (b.comment_created_at or "")
  end)

  return items
end

-------------------------------------------------------------------------------
-- Data Fetching
-------------------------------------------------------------------------------

-- Fetch all threads from GitHub via GraphQL (async)
-- @param callback function - Called with parsed items or nil on error
local function fetch_threads(callback)
  local query = build_graphql_query()
  local my_username = get_username()

  if not my_username or my_username == "" then
    vim.notify("Failed to get GitHub username. Run 'gh auth login' first.", vim.log.levels.ERROR)
    callback(nil)
    return
  end

  vim.system({
    "gh",
    "api",
    "graphql",
    "-f",
    "query=" .. query,
  }, { text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        local err_msg = result.stderr or "Unknown error"
        vim.notify("Failed to fetch threads: " .. err_msg, vim.log.levels.ERROR)
        callback(nil)
        return
      end

      local ok, response = pcall(vim.json.decode, result.stdout)
      if not ok then
        vim.notify("Failed to parse GraphQL response", vim.log.levels.ERROR)
        callback(nil)
        return
      end

      -- Check for GraphQL errors
      if response.errors then
        local err_msgs = vim.tbl_map(function(e)
          return e.message or "Unknown error"
        end, response.errors)
        vim.notify("GraphQL errors: " .. table.concat(err_msgs, ", "), vim.log.levels.ERROR)
        callback(nil)
        return
      end

      if not response.data then
        vim.notify("No data in GraphQL response", vim.log.levels.ERROR)
        callback(nil)
        return
      end

      -- Parse and process the response
      local items = parse_graphql_response(response.data, my_username)
      callback(items)
    end)
  end)
end

-------------------------------------------------------------------------------
-- Picker Formatter
-------------------------------------------------------------------------------

-- Format a single item for picker display
-- Display: [TYPE] PR #123 repo/name "body..." 2h
-- @param item table - Picker item
-- @param _picker table - Snacks picker instance (required by Snacks API, unused here)
-- @return table - Array of {text, highlight} tuples
local function format_item(item, _picker)
  local align = require("snacks.picker.util").align
  local ret = {}

  local current_repo = get_current_repo()
  local is_current_repo = item.repo == current_repo

  -- Type badge with color based on type and repo
  local type_display = ({
    needs_attention = "ATTENTION",
    my_pr = "MY_PR",
    pending = "PENDING",
  })[item.type] or item.type:upper()

  local type_hl
  if not is_current_repo then
    type_hl = "Comment" -- Dimmed for other repos
  elseif item.type == "needs_attention" then
    type_hl = "DiagnosticError" -- Red
  elseif item.type == "my_pr" then
    type_hl = "DiagnosticWarn" -- Orange
  else -- pending
    type_hl = "DiagnosticHint" -- Yellow
  end

  ret[#ret + 1] = { align("[" .. type_display .. "]", 12), type_hl }

  -- Kind and number (PR/Issue #123)
  local kind_display = item.kind == "pr" and "PR" or "Issue"
  local number_text = kind_display .. " #" .. item.number
  ret[#ret + 1] = { " " .. align(number_text, 12), is_current_repo and "SnacksPickerIdx" or "Comment" }

  -- Repository name (truncated)
  local repo_display = item.repo
  if #repo_display > 20 then
    -- Show just the repo name if too long
    repo_display = repo_display:match("/(.+)$") or repo_display
  end
  ret[#ret + 1] = { " " .. align(repo_display, 20), is_current_repo and "SnacksPickerDir" or "Comment" }

  -- Time since comment (between repo and comment for easy scanning)
  local time_str = iso_to_relative(item.comment_created_at)
  ret[#ret + 1] = { " " .. align(time_str, 4), is_current_repo and "SnacksPickerIdx" or "Comment" }

  -- Comment body preview (truncated)
  local body_preview = truncate(item.comment_body, 40)
  ret[#ret + 1] = { ' "' .. body_preview .. '"', is_current_repo and "SnacksPickerComment" or "Comment" }

  -- Build fuzzy searchable text
  item.text = table.concat(
    vim.tbl_map(function(seg)
      return seg[1]
    end, ret),
    ""
  )

  return ret
end

-------------------------------------------------------------------------------
-- Picker Preview
-------------------------------------------------------------------------------

-- Generate markdown preview for the selected item
-- Shows full thread context with all comments
-- @param ctx table - Picker context with ctx.item and ctx.preview
local function generate_preview(ctx)
  ctx.preview:reset()

  local item = ctx.item
  if not item then
    ctx.preview:set_lines({ "No thread selected" })
    return
  end

  local lines = {}
  local my_username = get_username()

  -- Header with type badge
  local type_display = ({
    needs_attention = "🔴 NEEDS ATTENTION",
    my_pr = "🟠 MY PR",
    pending = "🟡 PENDING",
  })[item.type] or item.type:upper()

  lines[#lines + 1] = "# " .. type_display
  lines[#lines + 1] = ""

  -- PR/Issue info
  local kind_display = item.kind == "pr" and "PR" or "Issue"
  lines[#lines + 1] = "## " .. kind_display .. " #" .. item.number .. ": " .. item.title
  lines[#lines + 1] = ""
  lines[#lines + 1] = "**Repository:** `" .. item.repo .. "`"

  if item.is_resolved then
    lines[#lines + 1] = "**Status:** ✅ Resolved"
  end

  lines[#lines + 1] = ""
  lines[#lines + 1] = "---"
  lines[#lines + 1] = ""
  lines[#lines + 1] = "## Thread Context"
  lines[#lines + 1] = ""

  -- Render all comments in the thread
  if item.thread_comments and #item.thread_comments > 0 then
    local num_comments = #item.thread_comments
    for i, comment in ipairs(item.thread_comments) do
      local author = comment.author and comment.author.login or "unknown"
      local time = iso_to_relative(comment.createdAt)

      -- Mark the author if it's me or if it's the last comment
      local author_suffix = ""
      if author == my_username then
        author_suffix = " (you)"
      end
      if i == num_comments then
        author_suffix = author_suffix .. " ← Latest"
      end

      lines[#lines + 1] = "**" .. author .. "**" .. author_suffix .. " (" .. time .. "):"
      lines[#lines + 1] = ""

      -- Quote the comment body
      if comment.body and comment.body ~= "" then
        for _, line in ipairs(vim.split(comment.body, "\n")) do
          lines[#lines + 1] = "> " .. line
        end
      else
        lines[#lines + 1] = "> *(empty comment)*"
      end

      lines[#lines + 1] = ""
    end
  else
    lines[#lines + 1] = "*No comments in this thread*"
  end

  -- NOTE: The reply action (r key) replies to the last comment in the selected thread
  -- using item.comment_database_id, not cursor position in the preview.
  -- Future enhancement: cursor-based reply would require attaching metadata via extmarks
  -- following the pattern in snacks.gh.render (line[#line + 1] = { "", meta = { comment_id = id } })

  ctx.preview:set_lines(lines)
  ctx.preview:highlight({ ft = "markdown" })
end

-------------------------------------------------------------------------------
-- Picker Actions
-------------------------------------------------------------------------------

-- Resolve or unresolve a PR review thread
-- @param item table - Picker item (must have thread_id)
-- @param resolve boolean - true to resolve, false to unresolve
-- @param callback function - Called after mutation completes
local function toggle_thread_resolved(item, resolve, callback)
  if not item.thread_id then
    vim.notify("Cannot resolve/unresolve: not a PR review thread", vim.log.levels.WARN)
    if callback then
      callback()
    end
    return
  end

  local mutation = resolve and "resolveReviewThread" or "unresolveReviewThread"
  local query = string.format(
    [[
    mutation {
      %s(input: { threadId: "%s" }) {
        thread { id isResolved }
      }
    }
  ]],
    mutation,
    item.thread_id
  )

  vim.system({
    "gh",
    "api",
    "graphql",
    "-f",
    "query=" .. query,
  }, { text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        vim.notify("Failed to " .. (resolve and "resolve" or "unresolve") .. " thread", vim.log.levels.ERROR)
      else
        item.is_resolved = resolve
        vim.notify(resolve and "✅ Thread resolved" or "↩️ Thread unresolved", vim.log.levels.INFO)
      end
      if callback then
        callback()
      end
    end)
  end)
end

-------------------------------------------------------------------------------
-- Main Picker
-------------------------------------------------------------------------------

-- Open the comment thread picker
M.picker = function()
  -- Show loading notification
  vim.notify("Fetching comment threads...", vim.log.levels.INFO)

  fetch_threads(function(items)
    if not items then
      return
    end

    -- Store items in state for toggle functionality
    state.items = items

    -- Apply initial filters and sort
    local filtered = apply_filters(items)
    local sorted = sort_items(filtered)

    if #sorted == 0 then
      local resolved_str = state.show_resolved and "resolved" or "unresolved"
      local hidden_str = state.show_hidden and "hidden" or "active"
      vim.notify("No " .. hidden_str .. " " .. resolved_str .. " threads found", vim.log.levels.INFO)
      return
    end

    Snacks.picker({
      -- Finder returns the pre-fetched and filtered items
      finder = function()
        return sorted
      end,
      format = format_item,
      preview = generate_preview,
      layout = "custom_horizontal",

      -- Main confirm action: open gh:// buffer
      confirm = function(picker, item)
        if not item then
          return
        end
        picker:close()
        local uri = string.format("gh://%s/%s/%d", item.repo, item.kind, item.number)
        vim.cmd("edit " .. uri)
      end,

      -- Custom actions
      actions = {
        -- Refresh: re-fetch all threads from GitHub
        refresh = function(picker)
          vim.notify("Refreshing threads...", vim.log.levels.INFO)
          fetch_threads(function(new_items)
            if new_items then
              state.items = new_items
              local new_filtered = apply_filters(new_items)
              local new_sorted = sort_items(new_filtered)
              -- Update the finder to return new items
              picker.finder._find = function()
                return new_sorted
              end
              picker:refresh()
              vim.notify("✅ Refreshed " .. #new_sorted .. " threads", vim.log.levels.INFO)
            end
          end)
        end,

        -- Toggle resolved view (<M-x>)
        -- Switch between showing unresolved vs resolved threads
        toggle_resolved_view = function(picker)
          state.show_resolved = not state.show_resolved
          local new_filtered = apply_filters(state.items)
          local new_sorted = sort_items(new_filtered)
          -- Replace finder with new filtered/sorted items
          picker.finder._find = function()
            return new_sorted
          end
          -- Use refresh() for proper UI update (as Snacks.gh does)
          picker:refresh()
        end,

        -- Toggle thread resolved (<C-x>)
        -- Mark a single thread as resolved or unresolved via GitHub API
        toggle_resolved = function(picker, item)
          if not item then
            return
          end
          if not item.thread_id then
            vim.notify("Only PR review threads can be resolved/unresolved", vim.log.levels.WARN)
            return
          end
          toggle_thread_resolved(item, not item.is_resolved, function()
            -- Refresh the list after toggling
            local new_filtered = apply_filters(state.items)
            local new_sorted = sort_items(new_filtered)
            picker.finder._find = function()
              return new_sorted
            end
            picker:refresh()
          end)
        end,

        -- Hide/unhide thread (<C-d>)
        -- NOTE: Named 'hide_thread' to avoid collision with Snacks' built-in 'toggle_hidden'
        -- action which toggles hidden files in file pickers
        -- Hidden threads are stored locally and will auto-unhide when new activity is detected
        hide_thread = function(picker, item)
          if not item then
            return
          end
          if state.hidden_threads[item.comment_url] then
            state.hidden_threads[item.comment_url] = nil
          else
            state.hidden_threads[item.comment_url] = os.time()
          end
          save_hidden_threads()
          local new_filtered = apply_filters(state.items)
          local new_sorted = sort_items(new_filtered)
          picker.finder._find = function()
            return new_sorted
          end
          picker:refresh()
        end,

        -- View hidden threads (<M-d>)
        -- NOTE: Named 'view_hidden_threads' to avoid collision with Snacks' built-in actions
        -- Switch between showing active threads vs hidden threads
        view_hidden_threads = function(picker)
          state.show_hidden = not state.show_hidden
          local new_filtered = apply_filters(state.items)
          local new_sorted = sort_items(new_filtered)
          picker.finder._find = function()
            return new_sorted
          end
          picker:refresh()
        end,

        -- Open in browser (S-CR)
        open_in_browser = function(_picker, item)
          if not item then
            return
          end
          local url = item.comment_url
          if url and url ~= "" then
            vim.ui.open(url)
          else
            vim.notify("No URL available for this comment", vim.log.levels.WARN)
          end
        end,

        -- Reply to comment (r key)
        -- This uses the snacks.gh reply mechanism
        reply = function(picker, item)
          if not item then
            return
          end

          -- For PR review thread comments (diff comments), use the /replies endpoint
          -- These have thread_id set - flat PR comments (conversation tab) don't have thread_id
          if item.kind == "pr" and item.thread_id and item.comment_database_id then
            local owner, repo_name = item.repo:match("(.+)/(.+)")
            if not owner or not repo_name then
              vim.notify("Invalid repo format", vim.log.levels.ERROR)
              return
            end

            -- Get preview window for scratch buffer positioning
            local preview_win = picker.preview and picker.preview.win
            if not preview_win or not preview_win:valid() then
              vim.notify("Preview window required for reply", vim.log.levels.WARN)
              return
            end

            -- Open scratch buffer at bottom of preview (context visible above)
            -- Uses same pattern as Snacks.gh for proper picker integration
            local height = 10
            Snacks.scratch({
              ft = "markdown",
              icon = " ",
              name = "Reply to " .. item.comment_author,
              win = {
                relative = "win",
                win = preview_win.win,
                width = 0,
                height = height,
                backdrop = false, -- Prevent backdrop from interfering with picker
                border = "top_bottom",
                row = function(win)
                  local border = win:border_size()
                  return win:parent_size().height - height - border.top - border.bottom
                end,
                wo = { winhighlight = "NormalFloat:Normal,FloatTitle:SnacksPickerTitle,FloatBorder:SnacksPickerBorder" },
                on_win = function(win)
                  -- Register window for picker's cycle_win navigation
                  vim.g.snacks_picker_cycle_win = win.win
                  vim.schedule(function()
                    vim.cmd.startinsert()
                  end)
                end,
                keys = {
                  submit = {
                    "<C-s>",
                    function(win)
                      local body = vim.trim(win:text())
                      if body == "" then
                        vim.notify("Reply cannot be empty", vim.log.levels.WARN)
                        return
                      end

                      -- Use the correct /replies endpoint for review thread comments
                      local endpoint = string.format(
                        "/repos/%s/%s/pulls/%d/comments/%d/replies",
                        owner,
                        repo_name,
                        item.number,
                        item.comment_database_id
                      )

                      vim.system({
                        "gh",
                        "api",
                        endpoint,
                        "-X",
                        "POST",
                        "-f",
                        "body=" .. body,
                      }, { text = true }, function(result)
                        vim.schedule(function()
                          if result.code ~= 0 then
                            vim.notify("Failed to post reply: " .. (result.stderr or ""), vim.log.levels.ERROR)
                          else
                            vim.notify("✅ Reply posted", vim.log.levels.INFO)
                            win:close()
                            picker.opts.actions.refresh(picker)
                          end
                        end)
                      end)
                    end,
                    desc = "Submit reply",
                    mode = { "n", "i" },
                  },
                },
              },
            })
          elseif item.kind == "pr" and not item.thread_id then
            -- For flat PR comments (conversation tab), use the issues endpoint
            -- Flat comments don't support reply threading - we add a new comment to the PR
            -- (PRs are also issues in GitHub's API, so /issues/{pr}/comments works)
            local owner, repo_name = item.repo:match("(.+)/(.+)")
            if not owner or not repo_name then
              vim.notify("Invalid repo format", vim.log.levels.ERROR)
              return
            end

            local preview_win = picker.preview and picker.preview.win
            if not preview_win or not preview_win:valid() then
              vim.notify("Preview window required for comment", vim.log.levels.WARN)
              return
            end

            local height = 10
            Snacks.scratch({
              ft = "markdown",
              icon = " ",
              name = "Comment on PR #" .. item.number,
              win = {
                relative = "win",
                win = preview_win.win,
                width = 0,
                height = height,
                backdrop = false, -- Prevent backdrop from interfering with picker
                border = "top_bottom",
                row = function(win)
                  local border = win:border_size()
                  return win:parent_size().height - height - border.top - border.bottom
                end,
                wo = { winhighlight = "NormalFloat:Normal,FloatTitle:SnacksPickerTitle,FloatBorder:SnacksPickerBorder" },
                on_win = function(win)
                  -- Register window for picker's cycle_win navigation
                  vim.g.snacks_picker_cycle_win = win.win
                  vim.schedule(function()
                    vim.cmd.startinsert()
                  end)
                end,
                keys = {
                  submit = {
                    "<C-s>",
                    function(win)
                      local body = vim.trim(win:text())
                      if body == "" then
                        vim.notify("Comment cannot be empty", vim.log.levels.WARN)
                        return
                      end

                      -- Use issues endpoint for flat PR comments (PRs are issues in GitHub API)
                      local endpoint = string.format("/repos/%s/%s/issues/%d/comments", owner, repo_name, item.number)
                      vim.system({
                        "gh",
                        "api",
                        endpoint,
                        "-X",
                        "POST",
                        "-f",
                        "body=" .. body,
                      }, { text = true }, function(result)
                        vim.schedule(function()
                          if result.code ~= 0 then
                            vim.notify("Failed to post comment: " .. (result.stderr or ""), vim.log.levels.ERROR)
                          else
                            vim.notify("✅ Comment posted", vim.log.levels.INFO)
                            win:close()
                            picker.opts.actions.refresh(picker)
                          end
                        end)
                      end)
                    end,
                    desc = "Submit comment",
                    mode = { "n", "i" },
                  },
                },
              },
            })
          elseif item.kind == "issue" then
            -- For issues, post a new comment (no threading)
            local owner, repo_name = item.repo:match("(.+)/(.+)")
            if not owner or not repo_name then
              vim.notify("Invalid repo format", vim.log.levels.ERROR)
              return
            end

            local preview_win = picker.preview and picker.preview.win
            if not preview_win or not preview_win:valid() then
              vim.notify("Preview window required for comment", vim.log.levels.WARN)
              return
            end

            local height = 10
            Snacks.scratch({
              ft = "markdown",
              icon = " ",
              name = "Comment on Issue #" .. item.number,
              win = {
                relative = "win",
                win = preview_win.win,
                width = 0,
                height = height,
                backdrop = false, -- Prevent backdrop from interfering with picker
                border = "top_bottom",
                row = function(win)
                  local border = win:border_size()
                  return win:parent_size().height - height - border.top - border.bottom
                end,
                wo = { winhighlight = "NormalFloat:Normal,FloatTitle:SnacksPickerTitle,FloatBorder:SnacksPickerBorder" },
                on_win = function(win)
                  -- Register window for picker's cycle_win navigation
                  vim.g.snacks_picker_cycle_win = win.win
                  vim.schedule(function()
                    vim.cmd.startinsert()
                  end)
                end,
                keys = {
                  submit = {
                    "<C-s>",
                    function(win)
                      local body = vim.trim(win:text())
                      if body == "" then
                        vim.notify("Comment cannot be empty", vim.log.levels.WARN)
                        return
                      end

                      local endpoint = string.format("/repos/%s/%s/issues/%d/comments", owner, repo_name, item.number)
                      vim.system({
                        "gh",
                        "api",
                        endpoint,
                        "-X",
                        "POST",
                        "-f",
                        "body=" .. body,
                      }, { text = true }, function(result)
                        vim.schedule(function()
                          if result.code ~= 0 then
                            vim.notify("Failed to post comment: " .. (result.stderr or ""), vim.log.levels.ERROR)
                          else
                            vim.notify("✅ Comment posted", vim.log.levels.INFO)
                            win:close()
                            picker.opts.actions.refresh(picker)
                          end
                        end)
                      end)
                    end,
                    desc = "Submit comment",
                    mode = { "n", "i" },
                  },
                },
              },
            })
          else
            vim.notify("Reply not supported for this item type", vim.log.levels.WARN)
          end
        end,
      },

      -- Keybindings: <C-key> = actions, <M-key> = toggles
      win = {
        input = {
          keys = {
            -- Actions (Ctrl)
            ["<C-g>"] = { "refresh", desc = "Refresh threads", mode = { "n", "i" } },
            ["<C-x>"] = { "toggle_resolved", desc = "Resolve/unresolve thread", mode = { "n", "i" } },
            ["<C-a>"] = { "reply", desc = "Reply to comment", mode = { "n", "i" } },
            ["<C-o>"] = { "open_in_browser", desc = "Open in browser", mode = { "n", "i" } },
            ["<C-d>"] = { "hide_thread", desc = "Hide/unhide thread", mode = { "n", "i" } },
            -- Toggles (Alt)
            ["<M-x>"] = { "toggle_resolved_view", desc = "Toggle resolved view", mode = { "n", "i" } },
            ["<M-d>"] = { "view_hidden_threads", desc = "View hidden threads", mode = { "n", "i" } },
          },
        },
        list = {
          keys = {
            -- Actions (Ctrl)
            ["<C-g>"] = { "refresh", desc = "Refresh threads", mode = { "n", "i" } },
            ["<C-x>"] = { "toggle_resolved", desc = "Resolve/unresolve thread", mode = { "n", "i" } },
            ["<C-a>"] = { "reply", desc = "Reply to comment", mode = { "n", "i" } },
            ["<C-o>"] = { "open_in_browser", desc = "Open in browser", mode = { "n", "i" } },
            ["<C-d>"] = { "hide_thread", desc = "Hide/unhide thread", mode = { "n", "i" } },
            -- Toggles (Alt)
            ["<M-x>"] = { "toggle_resolved_view", desc = "Toggle resolved view", mode = { "n", "i" } },
            ["<M-d>"] = { "view_hidden_threads", desc = "View hidden threads", mode = { "n", "i" } },
          },
        },
        preview = {
          keys = {
            -- Actions (Ctrl)
            ["<C-g>"] = { "refresh", desc = "Refresh threads", mode = { "n", "i" } },
            ["<C-x>"] = { "toggle_resolved", desc = "Resolve/unresolve thread", mode = { "n", "i" } },
            ["<C-a>"] = { "reply", desc = "Reply to comment", mode = { "n", "i" } },
            ["<C-o>"] = { "open_in_browser", desc = "Open in browser", mode = { "n", "i" } },
            ["<C-d>"] = { "hide_thread", desc = "Hide/unhide thread", mode = { "n", "i" } },
            -- Toggles (Alt)
            ["<M-x>"] = { "toggle_resolved_view", desc = "Toggle resolved view", mode = { "n", "i" } },
            ["<M-d>"] = { "view_hidden_threads", desc = "View hidden threads", mode = { "n", "i" } },
          },
        },
      },
    })
  end)
end

-- Get thread counts for dashboard display (optional)
-- @return table - { pending = N, needs_attention = N, my_pr = N }
M.get_thread_counts = function()
  local counts = { pending = 0, needs_attention = 0, my_pr = 0 }
  for _, item in ipairs(state.items) do
    if not item.is_resolved and counts[item.type] then
      counts[item.type] = counts[item.type] + 1
    end
  end
  return counts
end

-- Get actionable thread count (for shell scripts calling headless Neovim)
-- Performs a synchronous fetch and returns count of threads needing response
-- @return number - Count of needs_attention + my_pr threads
M.get_actionable_count = function()
  local query = build_graphql_query()
  local my_username = get_username()

  if not my_username or my_username == "" then
    return 0
  end

  -- Synchronous fetch using :wait()
  local result = vim
    .system({
      "gh",
      "api",
      "graphql",
      "-f",
      "query=" .. query,
    }, { text = true })
    :wait()

  if result.code ~= 0 then
    return 0
  end

  local ok, response = pcall(vim.json.decode, result.stdout)
  if not ok or not response.data then
    return 0
  end

  -- Parse and count actionable threads
  local items = parse_graphql_response(response.data, my_username)
  local count = 0
  for _, item in ipairs(items) do
    -- Count unresolved needs_attention and my_pr threads (excluding hidden)
    if not item.is_resolved and (item.type == "needs_attention" or item.type == "my_pr") then
      -- Check if hidden (same logic as filter_by_hidden)
      local is_hidden = state.hidden_threads[item.comment_url] ~= nil
      if is_hidden then
        local comment_time = iso_to_unix(item.comment_created_at)
        local hide_timestamp = state.hidden_threads[item.comment_url]
        if comment_time and hide_timestamp and comment_time > hide_timestamp then
          is_hidden = false -- Auto-unhide due to new activity
        end
      end
      if not is_hidden then
        count = count + 1
      end
    end
  end

  return count
end

return M
