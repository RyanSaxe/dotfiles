-- List editing for Markdown: continuation, a clean exit off an empty bullet,
-- ordered-list increment, checkbox carry-forward, and checkbox toggle.
--
-- Its default keymaps are off because they claim insert <Tab> and <S-Tab>,
-- which the completion contract already owns. That collision is not
-- survivable: completion.lua's <Tab> chain ends in `nvim_feedkeys(..., "n",
-- false)`, and noremap feeds a literal Tab straight past any buffer-local map.
-- Indent and dedent stay native <C-t> / <C-d>.
--
-- <CR> composes instead of colliding. Blink's <CR> is `{ "accept", "fallback" }`
-- and its fallback resolves the buffer-local mapping below; markdown-plus in
-- turn hands the key back whenever the cursor is not in a list.
--
-- The <Plug> targets are registered when markdown-plus enables a buffer, so
-- these are buffer-local and hang off the same FileType event.

---@param buf integer
local function map_list_keys(buf)
  ---@param mode string|string[]
  ---@param lhs string
  ---@param action string
  ---@param desc string
  local function map(mode, lhs, action, desc)
    vim.keymap.set(mode, lhs, ("<Plug>(MarkdownPlus%s)"):format(action), { buffer = buf, desc = desc })
  end

  map("i", "<CR>", "ListEnter", "Continue list")
  map("n", "o", "NewListItemBelow", "New list item below")
  map("n", "O", "NewListItemAbove", "New list item above")
  map({ "n", "x" }, "<leader>ox", "ToggleCheckbox", "Toggle checkbox")
end

return {
  "YousefHadder/markdown-plus.nvim",
  ft = "markdown",
  opts = { keymaps = { enabled = false } },
  init = function()
    vim.api.nvim_create_autocmd("FileType", {
      group = vim.api.nvim_create_augroup("markdown_plus_keys", { clear = true }),
      pattern = "markdown",
      ---@param args vim.api.keyset.create_autocmd.callback_args
      callback = function(args)
        map_list_keys(args.buf)
      end,
    })
  end,
}
