-- which-key.nvim  ── Keybinding hints and custom group names
-- Adds descriptive names and icons for custom keybinding groups

return {
  "folke/which-key.nvim",
  opts = function(_, opts)
    -- show popup quickly without triggering on normal command sequences like dd
    opts.delay = 200
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
