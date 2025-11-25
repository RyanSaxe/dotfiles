# Dependency Picker

Smart dependency navigation for multiple programming languages. Navigate and search through project dependencies and standard libraries with intelligent auto-detection and configurable behavior.

## Supported Languages

- **Neovim** - Neovim plugins (lazy.nvim, packer.nvim, vim-plug)
- **Lua** - Lua packages (luarocks, lua_modules)
- **Python** - Python packages (virtualenv site-packages) and stdlib
- **JavaScript/TypeScript** - Node.js packages (node_modules)
- **Go** - Go packages (GOMODCACHE)
- **Rust** - Rust crates (cargo registry and git dependencies)
- **Ruby** - Ruby gems (rubygems)

## Features

- **Smart detection**: Auto-detects language from current filetype
- **Context awareness**: If you're inside a package directory, searches that package directly
- **Multi-detector handling**: Configurable logic for choosing between multiple package ecosystems
- **Language filtering**: Enable/disable specific languages
- **Dual modes**: Grep content or search files
- **Stdlib support**: Search language standard libraries

## Configuration

Call `setup()` in your Neovim configuration to customize behavior:

```lua
require("dependency-picker").setup({
  -- Optional: Whitelist specific languages (default: all enabled)
  -- Available: "neovim", "lua", "python", "javascript", "go", "rust", "ruby"
  enabled_languages = nil,  -- nil = all languages enabled

  -- Optional: Custom detector selection logic (default: first match)
  -- Called when multiple detectors match the current filetype
  select_detector = function(matching_detectors, context)
    -- matching_detectors: array of { detector = module, result = detect_result }
    -- context: { bufpath = string, filetype = string }
    
    -- Return the selected match, or nil to use first match
    return matching_detectors[1]
  end
})
```

### Example: Path-Based Selection

Prefer Neovim packages when "nvim" is in the file path, otherwise use Lua packages:

```lua
require("dependency-picker").setup({
  select_detector = function(matching_detectors, context)
    -- If "nvim" is anywhere in the absolute path, prefer Neovim detector
    if context.bufpath:match("nvim") then
      for _, match in ipairs(matching_detectors) do
        if match.detector.name == "Neovim" then
          return match
        end
      end
    end
    -- Default: return first match
    return matching_detectors[1]
  end
})
```

### Example: Filetype-Based Selection

```lua
require("dependency-picker").setup({
  select_detector = function(matching_detectors, context)
    -- For lua files in a neovim config, prefer Neovim
    -- For other lua files, prefer Lua packages
    if context.filetype == "lua" and context.bufpath:match("%.config/nvim") then
      for _, match in ipairs(matching_detectors) do
        if match.detector.name == "Neovim" then
          return match
        end
      end
    end
    return matching_detectors[1]
  end
})
```

### Example: Language Whitelist

Only enable Neovim, Lua, and Python:

```lua
require("dependency-picker").setup({
  enabled_languages = { "neovim", "lua", "python" }
})
```

## Usage

The plugin provides several search modes:

### Smart Search (Auto-detect)

- `M.smart_search("grep")` - Auto-detect language and grep packages
- `M.smart_search("files")` - Auto-detect language and search files
- `M.smart_search_stdlib("grep")` - Auto-detect and search stdlib

### Manual Search (Choose language)

- `M.manual_search("grep")` - Choose language, then grep packages
- `M.manual_search("files")` - Choose language, then search files
- `M.manual_search_stdlib("grep")` - Choose stdlib, then search

## How Multi-Detector Selection Works

When you're in a Lua file and run smart search:

1. Both "Lua" and "Neovim" detectors match the lua filetype
2. The `select_detector` function is called with both matches
3. Your custom logic chooses which detector to use
4. The selected package ecosystem is searched automatically

Without a custom `select_detector`, the first matching detector is used.

## API

### `M.setup(opts)`

Configure the dependency picker. See Configuration section above.

### `M.smart_search(mode)`

Auto-detect language and search. Modes: `"grep"` or `"files"`

### `M.manual_search(mode)`  

Manual language selection, then search. Modes: `"grep"` or `"files"`

### `M.smart_search_stdlib(mode)`

Auto-detect language and search stdlib. Modes: `"grep"` or `"files"`

### `M.manual_search_stdlib(mode)`

Manual stdlib selection, then search. Modes: `"grep"` or `"files"`

## Keybindings Example

```lua
vim.keymap.set("n", "<leader>ps", function() require("dependency-picker").smart_search("grep") end)
vim.keymap.set("n", "<leader>pS", function() require("dependency-picker").manual_search("grep") end)
vim.keymap.set("n", "<leader>pf", function() require("dependency-picker").smart_search("files") end)
vim.keymap.set("n", "<leader>pF", function() require("dependency-picker").manual_search("files") end)
vim.keymap.set("n", "<leader>pb", function() require("dependency-picker").smart_search_stdlib("grep") end)
vim.keymap.set("n", "<leader>pB", function() require("dependency-picker").manual_search_stdlib("grep") end)
```
