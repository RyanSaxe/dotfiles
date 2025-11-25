---
description:
  Neovim and Lua development with LazyVim conventions and TokyoNight theme
  consistency
---

# Task

Work with Neovim configuration, Lua scripts, LazyVim plugins, and ensure
TokyoNight theme consistency.

## Core Principles

- **LazyVim Base**: This config uses LazyVim with custom plugins in
  `nvim/lua/plugins/`
- **Lua 5.4.7**: Target Lua 5.4.7 (Neovim 0.11.2)
- **Detailed Comments**: Unlike other code, leave detailed comments in
  Neovim/Lua configs
  - APIs are complex and configs are frequently modified
  - Explain WHY, not just WHAT
- **Theme Consistency**: Match TokyoNight colors for any customizations
  - Reference: `nvim/lua/plugins/colorscheme.lua`

## LazyVim Structure

LazyVim plugins live in `nvim/lua/plugins/`:

```lua
-- nvim/lua/plugins/example.lua
return {
  "author/plugin-name",
  dependencies = { "dependency/plugin" },
  opts = {
    -- Options passed to setup()
  },
  keys = {
    { "<leader>x", "<cmd>Command<cr>", desc = "Description" },
  },
  config = function()
    -- Custom setup if needed
    require("plugin-name").setup({ ... })
  end,
}
```

## Lazy Loading Patterns

Load plugins efficiently:

```lua
-- Load when command exists
{ "plugin/name", cond = function() return vim.fn.executable("tool") == 1 end }

-- Load on event
{ "plugin/name", event = "BufReadPre" }

-- Load on filetype
{ "plugin/name", ft = { "python", "lua" } }

-- Load on keymap
{ "plugin/name", keys = { "<leader>x" } }
```

## Neovim API Patterns

Common operations:

```lua
-- Keymaps
vim.keymap.set("n", "<leader>x", function()
  -- Action
end, { desc = "Description" })

-- Autocommands
vim.api.nvim_create_autocmd("FileType", {
  pattern = "lua",
  callback = function()
    -- Action
  end,
})

-- User commands
vim.api.nvim_create_user_command("CommandName", function(opts)
  -- Implementation
  -- opts.args, opts.fargs available
end, { nargs = "?" })

-- Options
vim.bo.filetype = "lua"       -- Buffer options
vim.wo.number = true          -- Window options
vim.o.ignorecase = true       -- Global options
```

## Theme Colors (TokyoNight)

When customizing colors:

```lua
-- Colors are at:
-- ~/.local/share/nvim/lazy/tokyonight.nvim/lua/tokyonight/colors/
-- ~/.local/share/nvim/lazy/tokyonight.nvim/lua/tokyonight/groups/

local colors = require("tokyonight.colors").setup()

vim.api.nvim_set_hl(0, "MyHighlight", {
  fg = colors.blue,
  bg = colors.bg_dark,
})
```

**Reference:** `nvim/lua/plugins/colorscheme.lua` in this dotfiles repo

## Write Detailed Comments

**Example:**

```lua
-- Define custom command to reload a module
-- Useful during plugin development to test changes without restarting Neovim
vim.api.nvim_create_user_command("ReloadModule", function(opts)
  local module = opts.args
  -- Clear module from package.loaded to force reload
  package.loaded[module] = nil
  -- Require again to load fresh version
  require(module)
  vim.notify("Reloaded " .. module, vim.log.levels.INFO)
end, { nargs = 1 })
```

## Testing Configuration

```bash
# Test config loads without errors
nvim --headless +quit

# Check startup time
nvim --startuptime startup.log

# Run with specific config
nvim -u /path/to/init.lua
```

## Related Documentation

- [Style Guide](~/.claude/references/style.md) - General code style
- [LazyVim docs](https://lazyvim.org) - LazyVim documentation
- Neovim API: `:h api` or `:h lua-guide`
