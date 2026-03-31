-- which-key.nvim  ── Keybinding hints and custom group names
-- Adds descriptive names and icons for custom keybinding groups

return {
  "folke/which-key.nvim",
  opts = function(_, opts)
    local wk_util = require("which-key.util")

    -- Show leader/localleader immediately, but keep a delay for other prefixes
    -- so normal command sequences like `dd` don't trigger the popup.
    opts.delay = function(ctx)
      if ctx.plugin then
        return 0
      end
      if ctx.keys == wk_util.norm("<leader>") or ctx.keys == wk_util.norm("<localleader>") then
        return 0
      end
      return 200
    end
    opts.spec = opts.spec or {}

    local function remove_ui_group(specs)
      for i = #specs, 1, -1 do
        local spec = specs[i]
        if type(spec) == "table" then
          if spec[1] == "<leader>u" and spec.group == "ui" then
            table.remove(specs, i)
          else
            remove_ui_group(spec)
          end
        end
      end
    end

    remove_ui_group(opts.spec)

    vim.list_extend(opts.spec, {
      { "<leader>a", group = "AI", icon = "󰚩" },
      { "<leader>o", group = "Obsidian", icon = "󰎞" },
      { "<leader>p", group = "Package", icon = "󰏗" },
      { "<leader>t", group = "Toggle", icon = "󰔡" },
      { "<leader>U", group = "UI" },
      -- Git diff groups
      { "<leader>gd", group = "Diff", icon = "" },
    })
  end,
}
