-- Annotation coverage for Lua, the half `lua-language-server --check`
-- cannot do. LuaLS reports values whose type it cannot INFER; it says
-- nothing about a function that happens to be inferable but is
-- undocumented. `local function join(a, b) return a .. b end` passes a
-- strict LuaLS run cleanly and is still undocumented.
--
-- The policy: every parameter is named in a `---@param`, and every
-- function that returns a value declares a `---@return`. Parameters
-- named `_` are ignored by convention, and `self` is implicit in method
-- syntax. A zero-argument function returning nothing needs no
-- annotation — there would be nothing to say.
--
-- Run via `nvim -l dev/annotation-check.lua`; treesitter does the
-- parsing, so this reads real syntax rather than guessing with patterns.
local script_dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
local root = vim.fs.normalize(script_dir .. "/..")

---@type string[]
local ROOTS = { root .. "/nvim/lua", root .. "/ci" }

---@param path string
---@return string[]
local function read_lines(path)
  return vim.fn.readfile(path)
end

-- The contiguous run of `---` comment lines immediately above a line.
---@param lines string[]
---@param start_row integer 0-indexed row of the function
---@return string
local function doc_block_above(lines, start_row)
  ---@type string[]
  local block = {}
  local row = start_row -- lines[] is 1-indexed, so this is the line above
  while row >= 1 and lines[row]:match("^%s*%-%-%-") do
    table.insert(block, 1, lines[row])
    row = row - 1
  end
  return table.concat(block, "\n")
end

---@param node TSNode
---@return TSNode|nil
local function enclosing_function(node)
  local parent = node:parent()
  while parent do
    local t = parent:type()
    if t == "function_declaration" or t == "function_definition" then
      return parent
    end
    parent = parent:parent()
  end
  return nil
end

-- Whether THIS function returns a value, ignoring returns that belong to
-- functions nested inside it.
---@param fn TSNode
---@param source string
---@return boolean
local function returns_a_value(fn, source)
  local query = vim.treesitter.query.parse("lua", "(return_statement) @ret")
  for _, node in query:iter_captures(fn, source) do
    if node:named_child_count() > 0 and enclosing_function(node) == fn then
      return true
    end
  end
  return false
end

---@param fn TSNode
---@param source string
---@return string[]
local function parameter_names(fn, source)
  local params = fn:field("parameters")[1]
  ---@type string[]
  local names = {}
  if not params then
    return names
  end
  for child in params:iter_children() do
    local t = child:type()
    if t == "identifier" or t == "vararg_expression" then
      local name = vim.treesitter.get_node_text(child, source)
      if name ~= "_" and name ~= "self" then
        names[#names + 1] = name
      end
    end
  end
  return names
end

---@param path string
---@return string[] findings
local function check_file(path)
  local source = table.concat(read_lines(path), "\n")
  local lines = read_lines(path)
  local parser = vim.treesitter.get_string_parser(source, "lua")
  local tree = parser:parse()[1]
  local query = vim.treesitter.query.parse(
    "lua",
    [[
    [(function_declaration) (function_definition)] @fn
  ]]
  )

  ---@type string[]
  local findings = {}
  for _, fn in query:iter_captures(tree:root(), source) do
    local start_row = fn:start()
    local doc = doc_block_above(lines, start_row)
    local rel = path:sub(#root + 2)

    for _, name in ipairs(parameter_names(fn, source)) do
      local pattern = name == "..." and "%-%-%-@param%s+%.%.%." or ("%-%-%-@param%s+" .. vim.pesc(name) .. "[%s%?]")
      if not doc:match(pattern) then
        findings[#findings + 1] = ("%s:%d: parameter `%s` has no ---@param"):format(rel, start_row + 1, name)
      end
    end

    if returns_a_value(fn, source) and not doc:match("%-%-%-@return") then
      findings[#findings + 1] = ("%s:%d: returns a value but has no ---@return"):format(rel, start_row + 1)
    end
  end
  return findings
end

---@type string[]
local all = {}
for _, dir in ipairs(ROOTS) do
  for _, path in ipairs(vim.fn.glob(dir .. "/**/*.lua", true, true)) do
    vim.list_extend(all, check_file(path))
  end
end

if #all == 0 then
  print("annotation-check: every function documents its parameters and return")
  os.exit(0)
end

table.sort(all)
for _, finding in ipairs(all) do
  io.write(finding, "\n")
end
io.write(("annotation-check: %d undocumented function signature(s)\n"):format(#all))
os.exit(1)
