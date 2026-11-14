-- Finds the blocks around the cursor whose headers have scrolled above the
-- window. nvim-treesitter-context's `context` queries say which nodes are
-- blocks and where each header ends; the rules for reading them follow that
-- plugin's lua/treesitter-context/context.lua.
local header = require("context_line.header")

local M = {}

---@class context_line.Block
---@field node TSNode
---@field start_row integer first row of the header, 0-based
---@field last_row integer last row of the header that has text

---@param lang string
---@return vim.treesitter.Query?
local function context_query(lang)
  local ok, query = pcall(vim.treesitter.query.get, lang, "context")
  if not ok then
    vim.notify_once(
      ("context-line: cannot load the context query for %s:\n%s"):format(lang, query),
      vim.log.levels.ERROR
    )
    return nil
  end
  return query
end

--- The language trees that contain `range`, outermost first.
---@param parser vim.treesitter.LanguageTree
---@param range Range4
---@return vim.treesitter.LanguageTree[]
local function language_trees(parser, range)
  local trees = { parser }
  while true do
    local inner
    for _, child in pairs(trees[#trees]:children()) do
      if child:contains(range) then
        inner = child
        break
      end
    end
    if not inner then
      return trees
    end
    trees[#trees + 1] = inner
  end
end

---@param langtree vim.treesitter.LanguageTree
---@param range Range4
---@return TSNode[] # outermost first
local function ancestors(langtree, range)
  local tree = langtree:tree_for_range(range, { ignore_injections = true })
  local node = tree and tree:root():named_descendant_for_range(unpack(range))
  local chain = {}
  while node do
    table.insert(chain, 1, node)
    node = node:parent()
  end
  return chain
end

---@param node TSNode
---@return boolean
local function in_comment(node)
  local parent = node:parent()
  return node:type():find("comment", 1, true) ~= nil
    or (parent ~= nil and parent:type():find("comment", 1, true) ~= nil)
end

--- The outermost node inside `block` that starts on the row `capture`
--- starts on and holds `capture`. Scala's query ends a case's header at
--- the first child of its first statement, and Ruby's ends a `case` at the
--- first child of its first `when`; ending the header where that statement
--- or `when` starts keeps its row out of the header.
---@param capture TSNode
---@param block TSNode
---@return TSNode
local function outermost_on_row(capture, block)
  local row = capture:start()
  local parent = capture:parent()
  while parent and parent ~= block and parent:start() == row do
    capture, parent = parent, parent:parent()
  end
  return capture
end

--- Where the header of a call ends: at the start of its argument list, or,
--- when the arguments sit one per row, after the first row of the argument
--- that holds the cursor, so the arguments above the cursor join the call's
--- row.
---@param arguments TSNode
---@param cursor_row integer
---@return integer end_row
---@return integer end_col
local function arguments_end(arguments, cursor_row)
  local open_row = arguments:start()
  local row = open_row
  for child in arguments:iter_children() do
    local child_row = child:start()
    if child_row > cursor_row then
      break
    elseif child:named() and not child:type():find("comment", 1, true) then
      row = child_row
    end
  end
  row = math.min(row, cursor_row - 1)
  if row <= open_row then
    local _, open_col = arguments:start()
    return open_row, open_col
  end
  return row + 1, 0
end

--- The node that `node` only wraps, such as the call in Java's statement
--- around it: its one named child, when that child starts where it does.
---@param node TSNode
---@return TSNode
local function unwrap(node)
  while node:named_child_count() == 1 do
    local child = node:named_child(0) --[[@as TSNode]]
    local row, col = node:start()
    local child_row, child_col = child:start()
    if child_row ~= row or child_col ~= col then
      return node
    end
    node = child
  end
  return node
end

--- Where the header of a node with no `body` field ends. When its first
--- child is bracketed, such as JSX's `<tr …>` opening tag, the header runs
--- through that child once the cursor is below it, and stays one row while
--- the cursor is inside it. When it ends with an argument list, or only
--- wraps a node that does, the header holds the whole callee, such as a
--- method chain, and the arguments above the cursor. Otherwise it ends
--- after its `condition` field, as in Bash's `if`, or after one row.
---@param node TSNode
---@param start_row integer
---@param cursor_row integer
---@return integer end_row
---@return integer end_col
local function bodiless_header_end(node, start_row, cursor_row)
  local first = node:child(0)
  if node:child_count() >= 2 and first and header.bracket_pair(first) then
    local end_row, end_col = first:end_()
    if end_row < cursor_row then
      return end_row, end_col
    end
    return start_row + 1, 0
  end
  local call = unwrap(node)
  local count = call:child_count()
  local last = call:child(count - 1)
  if count >= 2 and last and last:type():find("argument") and header.bracket_pair(last) then
    return arguments_end(last, cursor_row)
  end
  local condition = node:field("condition")[1]
  if condition then
    return condition:end_()
  end
  return start_row + 1, 0
end

--- Where the query says the header of `node` starts and ends, from the
--- matches of the patterns rooted at `root`. A query with no end capture
--- leaves the header at one row; this reads up to the start of the node's
--- `body` field instead, so a multi-line `for` header is whole. A match that
--- ends the header at a comment is skipped, because comments are dropped
--- from the line and a later end then still holds.
---@param root TSNode `node` or its parent
---@param node TSNode
---@param bufnr integer
---@param query vim.treesitter.Query
---@param cursor_row integer
---@return integer? start_row
---@return integer end_row exclusive end position of the header
---@return integer end_col
local function match_header(root, node, bufnr, query, cursor_row)
  for _, match in query:iter_matches(root, bufnr, 0, -1, { max_start_depth = 0 }) do
    local is_block, ends_at_comment = false, false
    local start_row = node:start()
    local end_row, end_col
    for id, nodes in pairs(match) do
      local capture = nodes[#nodes]
      local name = query.captures[id]
      if name == "context" then
        is_block = is_block or capture == node
      elseif name == "context.start" then
        start_row = capture:start()
      elseif name == "context.end" then
        -- A quantified capture, such as Ruby's for each `when` of a `case`,
        -- holds several nodes in order, and the header ends at the first.
        end_row, end_col = outermost_on_row(nodes[1], node):start()
        ends_at_comment = in_comment(nodes[1])
      elseif name == "context.final" then
        end_row, end_col = capture:end_()
        ends_at_comment = in_comment(capture)
      end
    end
    if is_block and not ends_at_comment then
      if not end_row then
        local body = node:field("body")[1]
        if body then
          end_row, end_col = body:start()
        else
          end_row, end_col = bodiless_header_end(node, start_row, cursor_row)
        end
      end
      return start_row, end_row, end_col
    end
  end
  return nil, 0, 0
end

--- Where the header of `node` starts and ends, or nil when it is no block.
--- A pattern can capture a child of its root as the block, as Elixir's does
--- for the right side of an operator, so the parent's patterns are read
--- when the node's own patterns make no block of it.
---@param node TSNode
---@param bufnr integer
---@param query vim.treesitter.Query
---@param cursor_row integer
---@return integer? start_row
---@return integer end_row exclusive end position of the header
---@return integer end_col
local function header_range(node, bufnr, query, cursor_row)
  local start_row, end_row, end_col = match_header(node, node, bufnr, query, cursor_row)
  local parent = node:parent()
  if not start_row and parent then
    return match_header(parent, node, bufnr, query, cursor_row)
  end
  return start_row, end_row, end_col
end

--- The last row before the header's end that has text on it.
---@param bufnr integer
---@param start_row integer
---@param end_row integer
---@param end_col integer
---@return integer
local function last_text_row(bufnr, start_row, end_row, end_col)
  if end_col == 0 then
    end_row, end_col = end_row - 1, -1
  end
  while end_row > start_row do
    local line = vim.api.nvim_buf_get_lines(bufnr, end_row, end_row + 1, false)[1] or ""
    if line:sub(1, end_col):find("%S") then
      break
    end
    end_row, end_col = end_row - 1, -1
  end
  return end_row
end

--- The row the header of `node` starts on, given the row the query starts
--- it on. A block can start partway through a row that opens by closing a
--- list begun on an earlier row: Dart's query names a function's body,
--- which follows a wrapped signature's `}) async {`, and Swift's trailing
--- closures follow wrapped arguments' `) {`. The header then starts where
--- the construct holding that list starts, so it reads as one declaration
--- or call.
---@param node TSNode
---@param bufnr integer
---@param row integer
---@return integer
local function declaration_row(node, bufnr, row)
  local node_row, node_col = node:start()
  local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ""
  local col = #line:match("^%s*")
  if row ~= node_row or col >= node_col then
    return row
  end
  local token = node:tree():root():descendant_for_range(row, col, row, col + 1)
  local list = token and token:parent()
  if not list then
    return row
  end
  local kind = list:type()
  local is_list = kind:find("parameter") ~= nil or kind:find("argument") ~= nil
  if not is_list or list:start() >= row or list:child(list:child_count() - 1) ~= token then
    return row
  end
  local holder, parent = list, list:parent()
  while parent and not vim.treesitter.is_ancestor(parent, node) do
    holder, parent = parent, parent:parent()
  end
  return (holder:start())
end

--- The row of the first item inside the opening bracket that is the only
--- text on `row` apart from comments, such as a table on its own row in a
--- list of tables, or nil when the row holds more.
---@param node TSNode
---@param bufnr integer
---@param row integer
---@return integer?
local function first_item_row(node, bufnr, row)
  local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ""
  local col = #line:match("^%s*")
  local open = node:tree():root():descendant_for_range(row, col, row, col + 1)
  local list = open and open:parent()
  if not open or not list then
    return nil
  end
  local list_open, close = header.bracket_pair(list)
  if list_open ~= open then
    return nil
  end
  local item = open:next_sibling()
  while item and item:type():find("comment", 1, true) do
    item = item:next_sibling()
  end
  if not item or item == close or item:start() == row then
    return nil
  end
  return (item:start())
end

---@param node TSNode
---@param bufnr integer
---@param query vim.treesitter.Query
---@param cursor_row integer
---@return context_line.Block?
local function block_for(node, bufnr, query, cursor_row)
  local start_row, end_row, end_col = header_range(node, bufnr, query, cursor_row)
  if not start_row or end_row < start_row then
    return nil
  end
  start_row = declaration_row(node, bufnr, start_row)
  local last_row = last_text_row(bufnr, start_row, end_row, end_col)
  -- A header that is only an opening bracket says nothing, so it runs on
  -- through the first row of what is inside.
  if last_row == start_row then
    last_row = first_item_row(node, bufnr, start_row) or last_row
  end
  -- The cursor's own row is in view below the header.
  last_row = math.max(start_row, math.min(last_row, cursor_row - 1))
  -- A node that starts at the end of its only header row, such as Markdown
  -- injected after a heredoc's opening quotes, has no header text.
  local node_row, node_col = node:start()
  if start_row == node_row and last_row == node_row then
    local line = vim.api.nvim_buf_get_lines(bufnr, node_row, node_row + 1, false)[1] or ""
    if not line:find("%S", node_col + 1) then
      return nil
    end
  end
  return { node = node, start_row = start_row, last_row = last_row }
end

--- The blocks to pin in `winid`, outermost first. A block shows when its
--- node starts above the rows the pinned headers cover, so each header
--- pinned lets one more start a row lower. The separator line under them
--- covers one more row, and the rows and line never reach the cursor.
--- Rows are counted on screen, where a closed fold takes one row, a wrapped
--- line several and a concealed line none.
---@param winid integer
---@param parser vim.treesitter.LanguageTree
---@param opts { max_lines: integer, trim_scope: "outer"|"inner", separator: string|false }
---@return context_line.Block[]
function M.find(winid, parser, opts)
  local bufnr = vim.api.nvim_win_get_buf(winid)
  local top_row = vim.fn.line("w0", winid) - 1
  local cursor = vim.api.nvim_win_get_cursor(winid)
  local row, col = cursor[1] - 1, cursor[2]
  local info = vim.fn.getwininfo(winid)[1]
  local text_top = info.winrow + info.winbar
  -- The screen row of a buffer row's first column, from the window's first
  -- text row; negative when that column is scrolled off the top.
  local function screen_row(buf_row)
    return vim.fn.screenpos(winid, buf_row + 1, 1).row - text_top
  end
  local separator_rows = opts.separator and 1 or 0
  local max_rows = math.min(opts.max_lines, screen_row(row) - separator_rows)
  if max_rows <= 0 then
    return {}
  end

  parser:parse({ top_row, vim.fn.line("w$", winid) })
  local range = { row, col, row, col + 1 }
  local blocks = {} ---@type context_line.Block[]
  for _, langtree in ipairs(language_trees(parser, range)) do
    local query = context_query(langtree:lang())
    if query then
      for _, node in ipairs(ancestors(langtree, range)) do
        local node_row = node:start()
        local covered = math.min(max_rows, #blocks) + (#blocks > 0 and separator_rows or 0)
        if node_row < top_row or screen_row(node_row) < covered then
          local block = block_for(node, bufnr, query, row)
          if block then
            -- A block that starts inside the previous block's header reads
            -- as part of it: one row from the outer start to the inner end.
            -- The outer node stays, since its tree holds all of that text
            -- when the inner block is in an injected language.
            local previous = blocks[#blocks]
            if previous and block.start_row <= previous.last_row then
              previous.last_row = block.last_row
            else
              blocks[#blocks + 1] = block
            end
          end
        end
      end
    end
  end

  while #blocks > max_rows do
    table.remove(blocks, opts.trim_scope == "inner" and #blocks or 1)
  end
  return blocks
end

return M
