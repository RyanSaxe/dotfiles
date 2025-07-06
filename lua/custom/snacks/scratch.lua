-- https://github.com/folke/snacks.nvim/discussions/765
-- edited from above for my own preferences
local M = {}

local column_widths = { 0, 0, 0, 0 }

local function update_column_widths(item)
  column_widths[1] = math.max(column_widths[1], vim.api.nvim_strwidth(item.cwd))
  column_widths[2] = math.max(column_widths[2], vim.api.nvim_strwidth(item.icon))
  column_widths[3] = math.max(column_widths[3], vim.api.nvim_strwidth(item.name))
  column_widths[4] = math.max(column_widths[4], vim.api.nvim_strwidth(item.branch))
end

local function process_item(item)
  item._path = item.file
  item.branch = item.branch or ""
  item.cwd = item.cwd and vim.fn.fnamemodify(item.cwd, ":p:~") or ""
  item.icon = item.icon or Snacks.util.icon(item.ft, "filetype")
  item.preview = { text = item.file, ft = item.ft }
  update_column_widths(item)
end

local function process_items(items)
  for _, item in ipairs(items) do
    process_item(item)
  end
end

---@param item   table   -- the PR item your finder produced
---@param picker table   -- Snacks passes the current picker object
---@return snacks.picker.Highlight[]
function M.format_scratch_row(item, picker)
  local a = Snacks.picker.util.align
  local ret = {} ---@type snacks.picker.Highlight[]
  ret[#ret + 1] = {
    a(Snacks.picker.util.truncpath(item.cwd, 20, { cwd = item.cwd }), 20),
    "SnacksPickerIdx",
  }
  ret[#ret + 1] = {
    a(item.branch, 30, { truncate = true }),
    "SnacksIndent3",
  }
  ret[#ret + 1] = {
    a(item.name .. "." .. item.preview.ft, 20, { truncate = true }),
    "SnacksIndent5",
  }

  -- Make the row fuzzy-searchable -- this is why we add the files from the diff
  item.text = table.concat(
    vim.tbl_map(function(seg)
      return seg[1]
    end, ret),
    ""
  )

  return ret
end

function M.select_scratch()
  local items = Snacks.scratch.list()
  process_items(items)

  Snacks.picker.pick({
    source = "scratch",
    items = items,
    format = M.format_scratch_row,
    -- display the contents of the buffer with syntax highlighting
    preview = function(ctx)
      ctx.preview:reset()
      local lines = vim.fn.readfile(ctx.item.file)
      ctx.preview:set_lines(lines)
      ctx.preview:highlight({ ft = ctx.item.preview.ft })
    end,
    layout = {
      layout = { title = " Select Scratch Buffer: " },
      preview = true,
      preset = function()
        return vim.o.columns >= 120 and "default" or "vertical"
      end,
    },
    on_change = function()
      vim.cmd.startinsert()
    end,
    win = {
      input = {
        keys = {
          ["<c-x>"] = { "delete", mode = { "i", "n" } },
        },
      },
    },
    actions = {
      delete = function(picker, item)
        for _, entry in ipairs(items) do
          if entry.cwd == item.cwd then
            os.remove(item.file)
          end
        end
        picker:close()
        M.select_scratch()
      end,
    },
    confirm = function(_, item)
      if item then
        Snacks.scratch.open({ icon = item.icon, file = item.file, name = item.name, ft = item.ft })
      end
    end,
  })
end

function M.new_scratch(filetypes)
  Snacks.picker.pick({
    source = "scratch",
    items = filetypes,
    format = "text",
    layout = {
      preset = "select",
      preview = false,
      layout = { title = " Select a filetype: ", border = "rounded" },
    },
    actions = {
      confirm = function(picker, item)
        picker:close()
        vim.schedule(function()
          local items = picker:items()
          if #items == 0 then
            Snacks.scratch({ ft = picker:filter().pattern })
          else
            Snacks.scratch({ ft = item.text })
          end
        end)
      end,
    },
  })
end

return M
