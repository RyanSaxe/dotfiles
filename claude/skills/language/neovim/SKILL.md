---
name: neovim
description: Neovim and Lua configuration patterns, plugin development, and LazyVim conventions. Use when working with Neovim configs, Lua scripts, or plugin customization.
---

# Neovim Development Skill

Use this skill when working with Neovim configuration, Lua scripts, or plugin development.

## Core Principles

- **LazyVim Base**: This configuration is LazyVim-based with custom plugins in `nvim/lua/plugins/`
- **Lua Version**: Lua 5.4.7 (used by Neovim 0.11.2)
- **Theme**: Always match TokyoNight theme colors for customizations
  - Reference: `nvim/lua/plugins/colorscheme.lua`
- **Comments**: Unlike other languages, leave **detailed comments** in Lua/Neovim config for clarity

## Theme Colors

When customizing colors, always reference TokyoNight:
```lua
-- Find colors at:
-- ~/.local/share/nvim/lazy/tokyonight.nvim/lua/tokyonight/colors/
-- ~/.local/share/nvim/lazy/tokyonight.nvim/lua/tokyonight/groups/

local colors = require("tokyonight.colors").setup()
```

## Plugin Structure (LazyVim)

Plugins are defined in `nvim/lua/plugins/` with the Lazy.nvim spec:

```lua
-- nvim/lua/plugins/example.lua
return {
  "author/plugin-name",
  dependencies = { "dependency/plugin" },
  opts = {
    -- Plugin options
  },
  keys = {
    { "<leader>x", "<cmd>Command<cr>", desc = "Description" },
  },
  config = function()
    -- Setup code
  end,
}
```

### Common Patterns

```lua
-- Conditional loading
{
  "plugin/name",
  cond = function()
    return vim.fn.executable("tool") == 1
  end,
}

-- Lazy loading by event
{
  "plugin/name",
  event = "BufReadPre",
}

-- Lazy loading by filetype
{
  "plugin/name",
  ft = { "python", "lua" },
}
```

## Lua Style Guide

- **Leave detailed comments**: Explain configuration choices and complex logic
- **Use local functions**: Keep scope minimal
- **Match existing patterns**: Follow LazyVim and existing plugin conventions
- **Use vim.notify for messages**: `vim.notify("Message", vim.log.levels.INFO)`

### Example with Comments

```lua
-- Define a custom command to reload a module
-- This is useful during plugin development to test changes without restarting Neovim
vim.api.nvim_create_user_command("ReloadModule", function(opts)
  local module = opts.args
  -- Clear the module from package.loaded to force reload
  package.loaded[module] = nil
  -- Require it again to load the fresh version
  require(module)
  vim.notify("Reloaded " .. module, vim.log.levels.INFO)
end, { nargs = 1 })
```

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
  -- Implementation
end, { nargs = "?" })

-- Buffer options
vim.bo.filetype = "lua"
vim.bo.expandtab = true

-- Window options
vim.wo.number = true
vim.wo.wrap = false

-- Global options
vim.o.ignorecase = true
vim.o.smartcase = true
```

## Testing Neovim Plugins with mini.test

Neovim plugin testing uses `mini.test` with `luassert` for assertions.

### Test Structure

```lua
local MyModule = require("mymodule")
local assert = require("luassert")

describe("mymodule functionality", function()
  local state

  before_each(function()
    -- Setup: runs before each test
    state = MyModule.new()
  end)

  after_each(function()
    -- Cleanup: runs after each test
    if state then
      MyModule.cleanup(state)
    end
  end)

  describe("initialization", function()
    it("initializes with correct defaults", function()
      MyModule.init(state)

      -- Multiple assertions for related checks (testing same concept)
      assert.equal(0, MyModule.get_count(state))
      assert.is_true(MyModule.is_enabled(state))
    end)

    it("handles nil safely", function()
      assert.has_no_errors(function()
        MyModule.init(nil)
      end)
    end)
  end)

  describe("error handling", function()
    it("propagates errors from wrapped function", function()
      local success, err = pcall(function()
        MyModule.with_handler(state, function()
          error("test error")
        end)
      end)

      assert.is_false(success)
      assert.matches("test error", err)
    end)
  end)
end)
```

### Test Runner Setup (minit.lua)

```lua
#!/usr/bin/env -S nvim -l

-- Set up isolated test environment
vim.env.LAZY_STDPATH = ".tests"

-- Setup lazy.nvim with test dependencies
require("lazy.minit").setup({
  spec = {
    {
      "echasnovski/mini.test",
      rocks = { "luassert" },
    },
    {
      dir = vim.uv.cwd(),
      name = "your-plugin.nvim",
      opts = {},
    },
  },
  rocks = {
    enabled = true,
  },
})
```

### Running Tests

```bash
# Run tests with test runner
nvim -l tests/minit.lua

# Or if using a test script
./tests/run_tests.sh
```

### Common Assertions

```lua
-- Equality
assert.equal(expected, actual)
assert.not_equal(expected, actual)

-- Boolean
assert.is_true(value)
assert.is_false(value)

-- Nil checks
assert.is_nil(value)
assert.is_not_nil(value)

-- Errors
assert.has_no_errors(function() ... end)
assert.has_error(function() ... end)

-- Pattern matching
assert.matches("pattern", string)
```

### Best Practices

- Use descriptive test names that explain the behavior
- Group related tests with `describe` blocks
- Use `before_each`/`after_each` for setup/teardown
- Test one concept per test (multiple assertions are fine if related)
- Test error cases and nil handling
- See [TDD skill](../../code/tdd/SKILL.md) for test-driven development workflow

### Testing Configuration

```bash
# Test Neovim config loads without errors
nvim --headless +quit

# Run Neovim with specific config
nvim -u /path/to/init.lua

# Check startup time
nvim --startuptime startup.log
```

## Further Reading

- [Detailed Style Guide](../../../references/style.md)
- [Development Workflow](../../../references/development.md)
- LazyVim docs: https://lazyvim.org
- Neovim API docs: `:h api`
