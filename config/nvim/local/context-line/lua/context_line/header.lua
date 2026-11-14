-- Collapses a block's header rows into one line. Comments are dropped,
-- tokens on different rows are joined by one space, and each token keeps the
-- Treesitter highlights of the text it came from.
local M = {}

local OPENERS = { ["("] = true, ["["] = true, ["{"] = true }
local CLOSERS = { [")"] = true, ["]"] = true, ["}"] = true }
local PAIRS = { ["("] = ")", ["["] = "]", ["{"] = "}", ["<"] = ">" }
local TRAILING = { [","] = true, [";"] = true }
local ACCESSORS = { ["."] = true, ["?."] = true, ["&."] = true, [".."] = true, ["?.."] = true }
local ELLIPSIS = "…"

---@class context_line.Chunk
---@field text string
---@field row integer source row, 0-based
---@field col integer source byte column
---@field gap "none"|"space"|"break" what separates it from the previous chunk in the source
---@field bracket? "open"|"close"
---@field infix? true punctuation between two parts of a node, such as the `.` of `a.b`
---@field attached? true an infix chunk written against the name after it, as `.` in `.b`
---@field leads_name? true an infix chunk that a name follows in its node, as `.` in `rows.Scan`
---@field trailing? true a comma that ends its list with nothing after it, as in a `where` clause
---@field added? true text the plugin wrote, with no source highlights

---@class context_line.Mark
---@field col integer
---@field end_col integer
---@field hl_group string
---@field priority integer

---@class context_line.List
---@field open TSNode
---@field close TSNode
---@field main? true a declaration's own parameters or a call's own arguments

--- The bracket tokens of a node that starts and ends with a matching pair,
--- such as `<` and `>` around type parameters.
---@param node TSNode
---@return TSNode? open
---@return TSNode? close
function M.bracket_pair(node)
  local count = node:child_count()
  if count < 2 then
    return nil, nil
  end
  local open, close = node:child(0), node:child(count - 1)
  if PAIRS[open:type()] ~= close:type() then
    return nil, nil
  end
  return open, close
end
local bracket_pair = M.bracket_pair

--- The node after `token` when `token` is punctuation between two parts of
--- the node it belongs to, such as the `.` of `a.b`, rather than a prefix
--- such as the `!` of `!b`. A member access token that opens a suffix, such
--- as the `.b` of Kotlin's and Swift's `a.b` or Dart's cascade `..b`, is
--- between parts when a value comes before the suffix. Other punctuation
--- that opens a node, such as an annotation's `@`, is a prefix even after
--- another annotation.
---@param token TSNode
---@return TSNode?
local function infix_operand(token)
  if token:named() or token:type():find("[%w_]") then
    return nil
  end
  local outer = token
  while outer:parent() and outer:parent():child_count() == 1 do
    outer = outer:parent() --[[@as TSNode]]
  end
  local after = outer:next_sibling()
  if not after or outer:prev_sibling() then
    return after
  end
  if not ACCESSORS[token:type()] then
    return nil
  end
  local opened = outer ---@type TSNode?
  while opened and not opened:prev_sibling() do
    opened = opened:parent()
  end
  local before = opened and opened:prev_sibling()
  return before and before:named() and after or nil
end

--- Whether nothing but comments follows `node` in its parent.
---@param node TSNode
---@return boolean
local function last_child(node)
  local sibling = node:next_sibling()
  while sibling and sibling:type():find("comment", 1, true) do
    sibling = sibling:next_sibling()
  end
  return sibling == nil
end

--- Splits the header rows into chunks: every token, and every run of
--- non-blank text that belongs to a node but to none of its children.
---@param top TSNode a node that covers the whole header
---@param lines string[] the header rows
---@param first_row integer
---@return context_line.Chunk[]
local function collect_chunks(top, lines, first_row)
  local last_row = first_row + #lines - 1
  local chunks = {} ---@type context_line.Chunk[]
  local end_row, end_col ---@type integer?, integer?
  local skipped_comment = false

  ---@param token? TSNode the token the text comes from
  local function add(row, col, text, bracket, token)
    bracket = bracket or (OPENERS[text] and "open") or (CLOSERS[text] and "close") or nil
    local gap = "none"
    if end_row and (skipped_comment or row > end_row) then
      gap = "break"
    elseif end_row and col > end_col then
      gap = "space"
    end
    -- A trailing comma or semicolon that ends a row before a closing
    -- bracket, or a comma that ends its list.
    local previous = chunks[#chunks]
    if gap == "break" and previous and (previous.trailing or (bracket == "close" and TRAILING[previous.text])) then
      table.remove(chunks)
    elseif gap == "none" and previous and previous.infix and text:find("^[%w_]") then
      previous.attached = true
    end
    local chunk = { text = text, row = row, col = col, gap = gap, bracket = bracket } ---@type context_line.Chunk
    if token and not token:named() then
      local operand = infix_operand(token)
      if operand then
        chunk.infix = true
        chunk.leads_name = not TRAILING[text] and operand:named() and operand:child_count() == 0 or nil
      end
      chunk.trailing = text == "," and last_child(token) or nil
    end
    chunks[#chunks + 1] = chunk
    end_row, end_col, skipped_comment = row, col + #text, false
  end

  -- Calls `each(row, from, text)` for the part of every header row inside
  -- the region from (row1, col1) to (row2, col2).
  local function each_row(row1, col1, row2, col2, each)
    for row = math.max(row1, first_row), math.min(row2, last_row) do
      local line = lines[row - first_row + 1]
      local from = row == row1 and col1 or 0
      local to = row == row2 and col2 or #line
      each(row, from, line:sub(from + 1, to))
    end
  end

  local function add_words(row1, col1, row2, col2)
    each_row(row1, col1, row2, col2, function(row, from, text)
      for start, word in text:gmatch("()(%S+)") do
        -- A backslash that ends a row only continues it, as in a C macro.
        local continues = word == "\\" and row < row2 and not text:find("%S", start + 1)
        if not continues then
          add(row, from + start - 1, word)
        end
      end
    end)
  end

  ---@param token TSNode
  ---@param bracket? "open"|"close"
  local function add_token(token, bracket)
    local row1, col1, row2, col2 = token:range()
    -- Tokens can hold blanks, such as a Markdown heading marker's indent.
    each_row(row1, col1, row2, col2, function(row, from, text)
      local trimmed = vim.trim(text)
      if trimmed ~= "" then
        add(row, from + #text:match("^%s*"), trimmed, bracket, token)
      end
    end)
  end

  ---@param node TSNode
  ---@param bracket? "open"|"close"
  local function walk(node, bracket)
    local srow, scol, erow, ecol = node:range()
    if erow < first_row or srow > last_row or (srow == erow and scol == ecol) then
      return
    end
    if node:type():find("comment", 1, true) then
      skipped_comment = true
      return
    end
    if node:child_count() == 0 then
      add_token(node, bracket)
      return
    end
    local open, close = bracket_pair(node)
    local row, col = srow, scol
    for child in node:iter_children() do
      local crow, ccol, cerow, cecol = child:range()
      if crow > row or (crow == row and ccol > col) then
        add_words(row, col, crow, ccol)
      end
      walk(child, (child == open and "open") or (child == close and "close") or nil)
      row, col = cerow, cecol
    end
    add_words(row, col, erow, ecol)
  end

  -- An injected language's tree can start or end partway through a header
  -- row, as in Svelte's `use:enhance={() => {`: the rest of the row is the
  -- host language's text.
  local srow, scol, erow, ecol = top:range()
  if srow == first_row then
    add_words(first_row, 0, first_row, scol)
  end
  walk(top)
  if erow == last_row then
    add_words(last_row, ecol, last_row, #lines[#lines])
  end
  return chunks
end

---@param name string a node type or field name
---@return boolean
local function names_list(name)
  return (name:find("parameter") or name:find("argument")) ~= nil
end

--- The comma before the last item of `list` that starts on or above
--- `last_row`, when `list` opens above `last_row` and closes below it, as
--- the arguments of a call that sit one per row do when the header holds
--- those above the cursor.
---@param list TSNode
---@param last_row integer
---@return TSNode?
local function last_comma_in(list, last_row)
  if list:start() >= last_row then
    return nil
  end
  local comma, before_item
  for item in list:iter_children() do
    if item:start() > last_row then
      break
    elseif item:type() == "," then
      comma = item
    elseif comma and item:named() and not item:type():find("comment", 1, true) then
      before_item = comma
    end
  end
  return before_item
end

--- The parameter and argument lists among the children of `node`: bracketed
--- nodes whose type or field names parameters or arguments, such as Scala's
--- block arguments, and parentheses whose first item is a parameter or
--- argument. The second kind covers Kotlin's primary constructors and
--- Swift's parameters, which sit straight in the declaration with no list
--- node around them. A list that runs on below the header ends at its last
--- comma in the header, so the items before it can empty.
---@param node TSNode
---@param last_row integer
---@return context_line.List[]
local function lists_in(node, last_row)
  local lists, opened = {}, {} ---@type context_line.List[], { open: TSNode, item?: TSNode }[]
  for child, field in node:iter_children() do
    if child:start() > last_row then
      break
    end
    local kind, innermost = child:type(), opened[#opened]
    if kind == "(" then
      opened[#opened + 1] = { open = child }
    elseif kind == ")" and innermost then
      opened[#opened] = nil
      if innermost.item and names_list(innermost.item:type()) then
        lists[#lists + 1] = { open = innermost.open, close = child }
      end
    elseif innermost and not innermost.item and child:named() and not kind:find("comment", 1, true) then
      innermost.item = child
    end
    local open, close = bracket_pair(child)
    if open and close and (names_list(kind) or (field ~= nil and names_list(field))) then
      if close:start() > last_row then
        close = last_comma_in(child, last_row)
      end
      if close then
        local main = field == "parameters" or field == "arguments"
        lists[#lists + 1] = { open = open, close = close, main = main or nil }
      end
    end
  end
  return lists
end

---@param name string a node type
---@return boolean
local function names_parameters(name)
  return (name:find("parameter") or name:find("formal")) ~= nil
end

--- The children of `node` that span rows and are a bracketed body of a
--- block nested in the header, such as a callback earlier in a method
--- chain, a group in braces, such as a struct type, or a string, whose rows
--- would join into text the source does not have. Braces that declare
--- parameters, such as a destructured argument or Nix's `{ pkgs, ... }:`,
--- keep their names.
---@param node TSNode
---@param last_row integer
---@return context_line.List[]
local function folded_in(node, last_row)
  local folded = {} ---@type context_line.List[]
  for child, field in node:iter_children() do
    local srow, _, erow = child:range()
    if srow > last_row then
      break
    end
    local count = child:child_count()
    local first, last = child:child(0), child:child(count - 1)
    if srow ~= erow and first and last then
      local is_body = field == "body" and bracket_pair(child) ~= nil
      local is_braces = first:type() == "{"
        and last:type() == "}"
        and not (names_parameters(child:type()) or names_parameters(node:type()))
      local is_string = child:type():find("string") ~= nil
        and count >= 2
        and first:child_count() == 0
        and last:child_count() == 0
      if is_body or is_braces or is_string then
        folded[#folded + 1] = { open = first, close = last }
      end
    end
  end
  return folded
end

--- The bracket pairs that `pairs_in` finds among the children of nodes in
--- the header and that lie wholly inside it, the shallowest first. Depth
--- counts the brackets around a pair rather than its depth in the tree, so
--- the calls of a method chain are equally deep. Of pairs equally deep, a
--- declaration's own parameters and a call's own arguments come first, so a
--- Go method's receiver and a function's type parameters stay longer.
--- Otherwise they go left to right.
---@param top TSNode
---@param first_row integer
---@param last_row integer
---@param pairs_in fun(node: TSNode, last_row: integer): context_line.List[]
---@return context_line.List[]
local function inner_lists(top, first_row, last_row, pairs_in)
  local found, seen = {}, {} ---@type { list: context_line.List, depth: integer, byte: integer }[], table<string, true>
  local queue, index = { { node = top, depth = 0 } }, 1
  while queue[index] do
    local parent = queue[index]
    local own_open, own_close = bracket_pair(parent.node)
    local depth = parent.depth + (own_open and 1 or 0)
    for _, list in ipairs(pairs_in(parent.node, last_row)) do
      local open_row, _, byte = list.open:start()
      local _, _, close_row = list.close:range()
      if open_row >= first_row and close_row <= last_row and not seen[list.open:id()] then
        seen[list.open:id()] = true
        -- A node's own brackets, such as a Kotlin primary constructor's, are
        -- not around the list they hold.
        local own = list.open == own_open and list.close == own_close
        found[#found + 1] = { list = list, depth = own and parent.depth or depth, byte = byte }
      end
    end
    for child in parent.node:iter_children() do
      local srow, _, erow = child:range()
      if srow > last_row then
        break
      elseif erow >= first_row then
        queue[#queue + 1] = { node = child, depth = depth }
      end
    end
    index = index + 1
  end
  table.sort(found, function(a, b)
    if a.depth ~= b.depth then
      return a.depth < b.depth
    elseif (a.list.main or false) ~= (b.list.main or false) then
      return a.list.main == true
    end
    return a.byte < b.byte
  end)
  return vim.tbl_map(function(item)
    return item.list
  end, found)
end

---@param previous context_line.Chunk
---@param chunk context_line.Chunk
---@return string
local function separator(previous, chunk)
  if chunk.gap == "none" then
    return ""
  end
  if chunk.gap == "space" then
    return " "
  end
  local inside_brackets = previous.bracket == "open" or chunk.bracket == "close"
  -- A chain of member accesses can break before its dot or after it.
  local in_chain = chunk.attached or (previous.leads_name and previous.gap == "none")
  return (inside_brackets or in_chain or chunk.text == ",") and "" or " "
end

---@param indent string
---@param chunks context_line.Chunk[]
---@return string text
---@return integer[] cols the byte column in `text` where each chunk starts
local function join(indent, chunks)
  local parts, cols, length = { indent }, {}, #indent
  for i, chunk in ipairs(chunks) do
    local sep = i > 1 and separator(chunks[i - 1], chunk) or ""
    cols[i] = length + #sep
    parts[#parts + 1] = sep .. chunk.text
    length = cols[i] + #chunk.text
  end
  return table.concat(parts), cols
end

---@param row integer
---@param col integer
---@param other_row integer
---@param other_col integer
---@return boolean
local function before(row, col, other_row, other_col)
  return row < other_row or (row == other_row and col < other_col)
end

--- Replaces the chunks between a list's brackets with one ellipsis.
---@param chunks context_line.Chunk[]
---@param list context_line.List
---@return boolean collapsed
local function collapse_list(chunks, list)
  local _, _, open_row, open_col = list.open:range()
  local close_row, close_col = list.close:start()
  local first, last
  for i, chunk in ipairs(chunks) do
    local inside = not before(chunk.row, chunk.col, open_row, open_col)
      and before(chunk.row, chunk.col, close_row, close_col)
    if inside then
      first, last = first or i, i
    end
  end
  if not first or (first == last and chunks[first].text == ELLIPSIS) then
    return false
  end
  local start = chunks[first]
  for _ = first, last do
    table.remove(chunks, first)
  end
  table.insert(chunks, first, { text = ELLIPSIS, row = start.row, col = start.col, gap = "none", added = true })
  if chunks[first + 1] then
    chunks[first + 1].gap = "none"
  end
  return true
end

--- Empties `lists` one at a time, in order, until the joined line fits in
--- `width` cells. A list whose ellipsis is no narrower than its contents
--- stays whole, and once the line fits, each list emptied before the last
--- is filled again if the line still fits with it whole.
---@param indent string
---@param chunks context_line.Chunk[]
---@param lists context_line.List[]
---@param width integer
---@return context_line.Chunk[] chunks
---@return string text
---@return integer[] cols
local function fit(indent, chunks, lists, width)
  ---@param emptied context_line.List[]
  local function build(emptied)
    local built = vim.deepcopy(chunks)
    for _, list in ipairs(emptied) do
      collapse_list(built, list)
    end
    local text, cols = join(indent, built)
    return { chunks = built, text = text, cols = cols, width = vim.api.nvim_strwidth(text), emptied = emptied }
  end

  local best = build({})
  for _, list in ipairs(lists) do
    if best.width <= width then
      break
    end
    local emptied = { unpack(best.emptied) }
    emptied[#emptied + 1] = list
    local next_try = build(emptied)
    if next_try.width < best.width then
      best = next_try
    end
  end
  if best.width <= width then
    local i = 1
    while i < #best.emptied do
      local kept = { unpack(best.emptied) }
      table.remove(kept, i)
      local next_try = build(kept)
      if next_try.width <= width then
        best = next_try
      else
        i = i + 1
      end
    end
  end
  return best.chunks, best.text, best.cols
end

--- Cuts `text` to `width` display cells, the last of them an ellipsis. It
--- cuts between grapheme clusters, so an emoji joined from several code
--- points stays whole.
---@param text string
---@param width integer
---@return string
local function truncate(text, width)
  local length, used = 0, 0
  for _, char in ipairs(vim.fn.split(text, [[\zs]])) do
    local char_width = vim.api.nvim_strwidth(char)
    if used + char_width > width - 1 then
      break
    end
    length, used = length + #char, used + char_width
  end
  local kept = text:sub(1, length):gsub("%s+$", "")
  -- A cut right after an ellipsis the line already has needs no second one.
  return vim.endswith(kept, ELLIPSIS) and kept or kept .. ELLIPSIS
end

--- Highlights for the chunks from the buffer's Treesitter highlight queries
--- and its language server, ranked so a later capture beats an earlier one
--- of the same priority, as in Neovim's own highlighter.
---@param parser vim.treesitter.LanguageTree
---@param bufnr integer
---@param chunks context_line.Chunk[]
---@param cols integer[]
---@param first_row integer
---@param last_row integer
---@return context_line.Mark[]
local function highlight_chunks(parser, bufnr, chunks, cols, first_row, last_row)
  local marks = {} ---@type context_line.Mark[]
  parser:for_each_tree(function(tstree, langtree)
    local lang = langtree:lang()
    local query = vim.treesitter.query.get(lang, "highlights")
    if not query then
      return
    end
    for id, node, metadata in query:iter_captures(tstree:root(), bufnr, first_row, last_row + 1) do
      local name = query.captures[id]
      if name:sub(1, 1) ~= "_" then
        local range = vim.treesitter.get_range(node, bufnr, metadata[id])
        local srow, scol, erow, ecol = range[1], range[2], range[4], range[5]
        for i, chunk in ipairs(chunks) do
          if not chunk.added and chunk.row >= srow and chunk.row <= erow then
            local chunk_end = chunk.col + #chunk.text
            local from = chunk.row == srow and math.max(scol, chunk.col) or chunk.col
            local to = chunk.row == erow and math.min(ecol, chunk_end) or chunk_end
            if to > from then
              marks[#marks + 1] = {
                col = cols[i] + from - chunk.col,
                end_col = cols[i] + to - chunk.col,
                hl_group = "@" .. name .. "." .. lang,
                priority = tonumber(metadata.priority) or vim.hl.priorities.treesitter,
              }
            end
          end
        end
      end
    end
  end)

  -- The language server's colors, for names it knows more about than
  -- Treesitter does, such as a parameter used in a function's body. They
  -- outrank Treesitter's colors at the priorities Neovim gives them.
  local ft = vim.bo[bufnr].filetype
  local base = vim.hl.priorities.semantic_tokens
  for i, chunk in ipairs(chunks) do
    if not chunk.added then
      local chunk_end = chunk.col + #chunk.text
      for _, token in ipairs(vim.lsp.semantic_tokens.get_at_pos(bufnr, chunk.row, chunk.col) or {}) do
        local from = token.line < chunk.row and chunk.col or math.max(token.start_col, chunk.col)
        local to = token.end_line > chunk.row and chunk_end or math.min(token.end_col, chunk_end)
        if to > from then
          local function add(group, delta)
            marks[#marks + 1] = {
              col = cols[i] + from - chunk.col,
              end_col = cols[i] + to - chunk.col,
              hl_group = group,
              priority = base + delta,
            }
          end
          add(("@lsp.type.%s.%s"):format(token.type, ft), 0)
          for modifier in pairs(token.modifiers) do
            add(("@lsp.mod.%s.%s"):format(modifier, ft), 1)
            add(("@lsp.typemod.%s.%s.%s"):format(token.type, modifier, ft), 2)
          end
        end
      end
    end
  end

  local order = {} ---@type table<context_line.Mark, integer>
  for i, mark in ipairs(marks) do
    order[mark] = i
  end
  table.sort(marks, function(a, b)
    if a.priority ~= b.priority then
      return a.priority < b.priority
    end
    return order[a] < order[b]
  end)
  for rank, mark in ipairs(marks) do
    mark.priority = rank
  end
  return marks
end

--- The cells that leading whitespace takes, each tab reaching the next
--- multiple of `tabstop`.
---@param leading string
---@param tabstop integer
---@return integer
local function indent_width(leading, tabstop)
  local width = 0
  for char in leading:gmatch(".") do
    width = char == "\t" and width + tabstop - width % tabstop or width + 1
  end
  return width
end

--- One line for `block` that fits in `width` cells, with its highlights.
--- The bodies of blocks nested in the header, such as callbacks, and
--- strings that span rows become an ellipsis. When the joined header is too
--- wide, the insides of its parameter and argument lists become an
--- ellipsis, shallowest first; if it is still too wide, its end is cut.
---@param parser vim.treesitter.LanguageTree
---@param bufnr integer
---@param block context_line.Block
---@param width integer
---@return string text
---@return context_line.Mark[]
function M.line(parser, bufnr, block, width)
  local first_row, last_row = block.start_row, block.last_row
  local lines = vim.api.nvim_buf_get_lines(bufnr, first_row, last_row + 1, false)
  local leading = lines[1]:match("^%s*")
  local indent = string.rep(" ", indent_width(leading, vim.bo[bufnr].tabstop))

  local root = block.node:tree():root()
  local top = root:descendant_for_range(first_row, #leading, last_row, #lines[#lines]) or root
  local chunks = collect_chunks(top, lines, first_row)
  -- Every language's tree, since a body can sit in an injected language,
  -- such as JavaScript in a Svelte attribute.
  parser:for_each_tree(function(tstree)
    local tree_root = tstree:root()
    local srow, _, erow = tree_root:range()
    if srow <= last_row and erow >= first_row then
      local from = tree_root:descendant_for_range(first_row, #leading, last_row, #lines[#lines]) or tree_root
      for _, list in ipairs(inner_lists(from, first_row, last_row, folded_in)) do
        collapse_list(chunks, list)
      end
    end
  end)

  local text, cols = join(indent, chunks)
  if vim.api.nvim_strwidth(text) > width then
    chunks, text, cols = fit(indent, chunks, inner_lists(top, first_row, last_row, lists_in), width)
  end

  local marks = highlight_chunks(parser, bufnr, chunks, cols, first_row, last_row)
  if vim.api.nvim_strwidth(text) > width then
    text = truncate(text, width)
    local limit = #text - #ELLIPSIS
    marks = vim.tbl_filter(function(mark)
      mark.end_col = math.min(mark.end_col, limit)
      return mark.col < mark.end_col
    end, marks)
  end
  return text, marks
end

return M
