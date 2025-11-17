# Testing Neovim Plugins with mini.test

Neovim plugin testing uses `mini.test` with `luassert` for assertions.

## Test Structure

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

## Test Runner Setup (minit.lua)

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

## Running Tests

```bash
# Run tests with test runner
nvim -l tests/minit.lua

# Or if using a test script
./tests/run_tests.sh
```

## Common Assertions

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

## Best Practices

- Use descriptive test names that explain the behavior
- Group related tests with `describe` blocks
- Use `before_each`/`after_each` for setup/teardown
- Test one concept per test (multiple assertions are fine if related)
- Test error cases and nil handling
- See [TDD skill](../code-tdd/SKILL.md) for test-driven development workflow

## Testing Configuration

```bash
# Test Neovim config loads without errors
nvim --headless +quit

# Run Neovim with specific config
nvim -u /path/to/init.lua

# Check startup time
nvim --startuptime startup.log
```

## Related

- [TDD skill](../code-tdd/SKILL.md) - Test-driven development workflow
- [Testing guide](../../../references/testing.md) - General testing patterns
