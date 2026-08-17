-- Slanted text-only tabs on the chrome surface: the tab row is the
-- identity layer (open buffers, plus the git branch right-aligned),
-- the statusline stays pure state. Active tab shares the editor's
-- base so it reads as connected; a dirty buffer's label turns warn.
return {
  "akinsho/bufferline.nvim",
  event = "VeryLazy",
  keys = {
    { "<leader>tb", "<cmd>set showtabline=0<cr>", desc = "Hide Bufferline" },
    { "<leader>tB", "<cmd>set showtabline=2<cr>", desc = "Show Bufferline" },
  },
  opts = function()
    local c = require("theme.chrome").colors()

    -- The branch is context, cached async so the tabline render never
    -- shells out.
    vim.api.nvim_create_autocmd({ "VimEnter", "DirChanged", "FocusGained" }, {
      group = vim.api.nvim_create_augroup("chrome_branch", { clear = true }),
      callback = function()
        vim.system({ "git", "rev-parse", "--abbrev-ref", "HEAD" }, { text = true }, function(out)
          local branch = out.code == 0 and vim.trim(out.stdout or "") or ""
          vim.schedule(function()
            vim.g.chrome_branch = branch
          end)
        end)
      end,
    })

    local tab = { bg = c.mantle, fg = c.muted }
    local tab_active = { bg = c.base, fg = c.text }
    local slant = { bg = c.mantle, fg = c.crust }
    local slant_active = { bg = c.base, fg = c.crust }

    return {
      options = {
        numbers = "none",
        separator_style = "slant",
        indicator = { style = "none" },
        show_buffer_icons = false,
        show_buffer_close_icons = false,
        show_close_icon = false,
        always_show_bufferline = true,
        diagnostics = false,
        custom_areas = {
          right = function()
            ---@type string
            local branch = vim.g.chrome_branch or ""
            if branch == "" then
              return {}
            end
            return { { text = "  " .. branch .. " ", fg = c.muted, bg = c.crust } }
          end,
        },
      },
      highlights = {
        fill = { bg = c.crust },
        background = tab,
        buffer_selected = { bg = c.base, fg = c.text, bold = false, italic = false },
        buffer_visible = tab,
        modified = { bg = c.mantle, fg = c.warn },
        modified_selected = { bg = c.base, fg = c.warn },
        modified_visible = { bg = c.mantle, fg = c.warn },
        separator = slant,
        separator_selected = slant_active,
        separator_visible = slant,
        duplicate = tab,
        duplicate_selected = tab_active,
        duplicate_visible = tab,
      },
    }
  end,
}
