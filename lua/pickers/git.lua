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

return M
