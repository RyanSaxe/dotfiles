# Neovim Development Skill

---
name: neovim
description: Neovim and Lua configuration patterns, plugin development, and LazyVim conventions. Use when working with Neovim configs, writing Lua scripts, creating plugins, customizing LazyVim, debugging Neovim issues, or matching TokyoNight theme colors.
---

## Quick Reference

**LazyVim plugin structure:**
```lua
return {
  "author/plugin-name",
  opts = { --[[options]] },
  keys = { { "<leader>x", "<cmd>Cmd<cr>", desc = "Desc" } },
}
```

**Neovim API:**
- Keymaps: `vim.keymap.set("n", "<leader>x", fn, { desc = "..." })`
- Autocommands: `vim.api.nvim_create_autocmd("Event", { ... })`
- Commands: `vim.api.nvim_create_user_command("Name", fn, {})`

**Related:**
- [Testing Neovim plugins](testing.md) - mini.test patterns
- [Style guide](../../../references/style.md) - Code style principles
- [LazyVim docs](https://lazyvim.org)

---

## Core Principles

- **LazyVim Base**: Configuration uses LazyVim with custom plugins in `nvim/lua/plugins/`
- **Lua Version**: 5.4.7 (Neovim 0.11.2)
- **Detailed Comments**: Unlike other languages, leave detailed comments in Lua/Neovim config
  - **Why**: Neovim APIs are hard to understand without context, configs are read/modified frequently
- **Theme Consistency**: Match TokyoNight theme colors for customizations
  - Reference: `nvim/lua/plugins/colorscheme.lua`

[General style principles →](../../../references/style.md)

---

## Plugin Structure (LazyVim)

Plugins are defined in `nvim/lua/plugins/` using Lazy.nvim spec:

```lua
-- nvim/lua/plugins/example.lua
return {
  "author/plugin-name",
  dependencies = { "dependency/plugin" },
  opts = {
    -- Plugin options (passed to setup())
  },
  keys = {
    { "<leader>x", "<cmd>Command<cr>", desc = "Description" },
  },
  config = function()
    -- Custom setup code if needed
    require("plugin-name").setup({
      -- options
    })
  end,
}
```

### Lazy Loading Patterns

```lua
-- Load when command is executable
{
  "plugin/name",
  cond = function()
    return vim.fn.executable("tool") == 1
  end,
}

-- Load on event
{
  "plugin/name",
  event = "BufReadPre", -- or "VeryLazy", "InsertEnter", etc.
}

-- Load on filetype
{
  "plugin/name",
  ft = { "python", "lua" },
}

-- Load on keymap
{
  "plugin/name",
  keys = { "<leader>x" },
}
```

---

## Lua Style Guide

- **Detailed comments**: Explain configuration choices and complex logic
- **Local functions**: Keep scope minimal (`local function name()`)
- **Match existing patterns**: Follow LazyVim and existing plugin conventions
- **Use vim.notify**: `vim.notify("Message", vim.log.levels.INFO)` for user messages

### Example with Comments

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

---

## Neovim API Common Operations

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
  -- Implementation with opts.args, opts.fargs, etc.
end, { nargs = "?" })

-- Options
vim.bo.filetype = "lua"       -- Buffer options
vim.wo.number = true          -- Window options
vim.o.ignorecase = true       -- Global options
```

---

## Theme Colors (TokyoNight)

When customizing colors, reference TokyoNight:

```lua
-- Find colors at:
-- ~/.local/share/nvim/lazy/tokyonight.nvim/lua/tokyonight/colors/
-- ~/.local/share/nvim/lazy/tokyonight.nvim/lua/tokyonight/groups/

local colors = require("tokyonight.colors").setup()

-- Use in highlights
vim.api.nvim_set_hl(0, "MyHighlight", {
  fg = colors.blue,
  bg = colors.bg_dark,
})
```

Reference: `nvim/lua/plugins/colorscheme.lua` in this project

---

## Testing Neovim Plugins

Use `mini.test` with `luassert` for testing Neovim plugins and configurations.

```lua
local assert = require("luassert")

describe("mymodule", function()
  it("does something", function()
    local result = require("mymodule").action()
    assert.equal(expected, result)
  end)
end)
```

[Full testing patterns →](testing.md)

---

## Configuration Testing

```bash
# Test config loads without errors
nvim --headless +quit

# Run with specific config
nvim -u /path/to/init.lua

# Check startup time
nvim --startuptime startup.log
```

---

## Related Resources

- [Testing patterns](testing.md) - mini.test and luassert
- [Style guide](../../../references/style.md) - General code style
- [Development workflow](../../../references/development.md) - Development process
- [LazyVim docs](https://lazyvim.org) - LazyVim documentation
- Neovim API: `:h api` or `:h lua-guide`
