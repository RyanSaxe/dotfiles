-- lua/pickers/simple_pr.lua
local M = {}

-----------------------------------------------------------------------
-- 1. Fetch every open PR (adds path+additions+deletions) -------------
-----------------------------------------------------------------------
function M.fetch_prs()
  local fields = table.concat({
    "number",
    "title",
    "author",
    "headRefName",
    "baseRefName",
    "isDraft",
    "labels",
    "files", -- << keep line counts
    "body",
  }, ",")

  local json_lines = vim.fn.systemlist({
    "gh",
    "pr",
    "list",
    "--state",
    "open",
    "--json",
    fields,
    "--jq",
    ".[] | @json",
  })

  local prs = {}
  for _, line in ipairs(json_lines) do
    local ok, obj = pcall(vim.json.decode, line)
    if ok then
      -- copy only what we need (keep path + counts)
      local files = {}
      for _, f in ipairs(obj.files or {}) do
        files[#files + 1] = {
          path = f.path,
          additions = f.additions or 0,
          deletions = f.deletions or 0,
        }
      end

      prs[#prs + 1] = {
        number = obj.number,
        title = obj.title,
        author = obj.author and obj.author.login or "",
        head = obj.headRefName,
        base = obj.baseRefName,
        draft = obj.isDraft,
        labels = vim.tbl_map(function(l)
          return l.name
        end, obj.labels or {}),
        files = files,
        body = obj.body or "",
        file = "~/.config/nvim/init.lua",
      }
    end
  end
  return prs
end

-----------------------------------------------------------------------
-- Format one PR row for Snacks.picker.format -------------------------
-- Expects each item to carry (at minimum):
--   number, title, additions, deletions, draft? (boolean), labels? {}
-----------------------------------------------------------------------
---@param item   table   -- the item your finder produced
---@param picker table   -- Snacks passes the current picker object
---@return snacks.picker.Highlight[]
function M.format_pr_row(item, picker)
  local a = Snacks.picker.util.align
  local ret = {} ---@type snacks.picker.Highlight[]
  ret[#ret + 1] = { a("#" .. tostring(item.number), 8, { truncate = true }), "SnacksPickerIdx" }

  if item.draft then
    ret[#ret + 1] = { "[DRAFT]", "SnacksPickerDimmed", virtual = true }
  else
    ret[#ret + 1] = { "[READY]", "SnacksPickerGitStatusAdded" }
  end

  ret[#ret + 1] = { " " }
  ret[#ret + 1] = { item.title or "<no title>", "SnacksPickerGitMsg" }

  if item.labels and #item.labels > 0 then
    ret[#ret + 1] = { " " }
    ret[#ret + 1] = {
      "[" .. table.concat(item.labels, ", ") .. "]",
      "SnacksPickerGitScope",
      virtual = true, -- keep the line length tidy
    }
  end

  return ret
end

-----------------------------------------------------------------------
-- 3. Markdown preview incl. file-level stats -------------------------
-----------------------------------------------------------------------
function M.preview_pr(ctx)
  local pr = ctx.item
  local out, add_sum, del_sum = {}, 0, 0

  out[#out + 1] = string.format("#%d  %s", pr.number, pr.title)
  out[#out + 1] = ""

  local function meta(lbl, val)
    if val and val ~= "" then
      out[#out + 1] = ("**%s:** %s"):format(lbl, val)
    end
  end
  meta("Author", pr.author)
  meta("Branch", pr.head and (pr.head .. " → " .. pr.base))
  meta("Labels", #pr.labels > 0 and table.concat(pr.labels, ", "))
  meta("Draft", pr.draft and "yes" or nil)

  out[#out + 1] = ""
  out[#out + 1] = pr.body ~= "" and pr.body or "*No description*"

  ------------------------------------------------------------------
  -- Git-style file summary
  ------------------------------------------------------------------
  if #pr.files > 0 then
    out[#out + 1] = ""
    out[#out + 1] = "**Files changed:**"

    -- width for nice alignment
    local w = 0
    for _, f in ipairs(pr.files) do
      w = math.max(w, #f.path)
      add_sum = add_sum + f.additions
      del_sum = del_sum + f.deletions
    end

    for _, f in ipairs(pr.files) do
      local bar = string.rep("+", f.additions) .. string.rep("-", f.deletions)
      out[#out + 1] = string.format("  %-*s │ %3d + %3d - │ %s", w, f.path, f.additions, f.deletions, bar)
    end

    out[#out + 1] = ""
    out[#out + 1] = string.format("**Total:** %d files | +%d −%d", #pr.files, add_sum, del_sum)
  end

  return table.concat(out, "\n")
end

--------------------------------------------------------------------------
-- Snacks plugin spec ---------------------------------------------------
--------------------------------------------------------------------------
---@param ... (string|string[]|nil)
local function git_args(...)
  local ret = { "-c", "core.quotepath=false" } ---@type string[]
  for i = 1, select("#", ...) do
    local arg = select(i, ...)
    vim.list_extend(ret, type(arg) == "table" and arg or { arg })
  end
  return ret
end

-- I add two custom fields to the snacks.picker.git.Config so I can pass base and head refs
---@class ExpandedGitConfig : snacks.picker.git.Config
---@field base  string?   # optional “base” ref
---@field head  string?   # optional “head” ref

---@param opts ExpandedGitConfig
---@type snacks.picker.finder
M.custom_diff = function(opts, ctx)
  if opts.base == nil and opts.head == nil then
    ARGS = git_args(opts.args, "--no-pager", "diff", "--no-color", "--no-ext-diff")
  elseif opts.head == nil then
    ARGS = git_args(opts.args, "--no-pager", "diff", opts.base, "--no-color", "--no-ext-diff")
  elseif opts.base == nil then
    error("base is required when head is provided")
  else
    ARGS = git_args(opts.args, "--no-pager", "diff", "--no-color", "--no-ext-diff", opts.base .. "..." .. opts.head)
  end
  local file, line ---@type string?, number?
  local header, hunk = {}, {} ---@type string[], string[]
  local header_len = 4
  local finder = require("snacks.picker.source.proc").proc({
    opts,
    { cmd = "git", args = ARGS },
  }, ctx)
  return function(cb)
    local function add()
      if file and line and #hunk > 0 then
        local diff = table.concat(header, "\n") .. "\n" .. table.concat(hunk, "\n")
        cb({
          text = file .. ":" .. line,
          diff = diff,
          file = file,
          pos = { line, 0 },
          preview = { text = diff, ft = "diff", loc = false },
        })
      end
      hunk = {}
    end
    finder(function(proc_item)
      local text = proc_item.text
      if text:find("diff", 1, true) == 1 then
        add()
        file = text:match("^diff .* a/(.*) b/.*$")
        header = { text }
        header_len = 4
      elseif file and #header < header_len then
        if text:find("^deleted file") or text:find("^new file") then
          header_len = 5
        end
        header[#header + 1] = text
      elseif text:find("@", 1, true) == 1 then
        add()
        -- Hunk header
        -- @example "@@ -157,20 +157,6 @@ some content"
        line = tonumber(string.match(text, "@@ %-.*,.* %+(.*),.* @@"))
        hunk = { text }
      elseif #hunk > 0 then
        hunk[#hunk + 1] = text
      else
        error("unexpected line: " .. text)
      end
    end)
    add()
  end
end

return M
