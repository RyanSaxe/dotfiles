# Neovim Keymap Restructuring Plan

## Context & Problem Statement

**Date:** August 27, 2025  
**Goal:** Create a clean, organized keymap structure for LazyVim-based Neovim config

### Current Issues
- Keymaps scattered across multiple files (`lua/config/keymaps.lua` + individual plugin files)
- Inconsistent prefix patterns (mixed `<leader>t*`, `<leader>p*`, etc.)
- No clear separation between personal workflow and LazyVim/plugin defaults
- Lack of organized structure makes it hard to remember and discover keymaps

### Current Keymap Examples
```lua
-- Scattered in lua/config/keymaps.lua:
vim.keymap.set("n", "<leader>tg", toggle_diffview, { desc = "Toggle Diffview" })
vim.keymap.set("n", "<leader>tG", toggle_diffview_with_prompt, { desc = "Toggle Diffview (prompt)" })
vim.keymap.set("n", "<leader>tp", toggle_pyright_diagnostic_mode, { desc = "Toggle basedpyright" })
vim.keymap.set("n", "<leader>ps", grep_venv_current_or_select, { desc = "Smart grep venv" })
vim.keymap.set("n", "<leader>pS", grep_venv_select, { desc = "Select and grep venv" })

-- Plus plugin-specific keymaps in individual plugin files
```

## Research Findings

### LazyVim Default Keymap Structure
**Leader:** `<space>` (default)  
**Localleader:** `\` (backslash, default)

**LazyVim uses these prefixes:**
- `<leader>c` - Code/Formatting  
- `<leader>d` - Diagnostics
- `<leader>f` - Files/Find
- `<leader>g` - Git operations
- `<leader>l` - Lazy plugin manager
- `<leader>q` - Quit actions
- `<leader>u` - UI/Toggles  
- `<leader>x` - Lists/Quickfix

**Key Insight:** LazyVim already has a well-established keymap structure with WhichKey integration.

## Evolution of Approach

### Initial Approach (Rejected)
Override LazyVim defaults and create our own structure - **Bad idea** because:
- Conflicts with LazyVim updates
- Loses familiar patterns for LazyVim users
- Fights against the framework

### Refined Approach (Partially Good)
Extend LazyVim defaults rather than replace them - **Better** but still has issues:
- Still cluttered with defaults we don't control
- Hard to maintain clean separation

### Final Approach (Chosen)
**Complete separation via leader key swap:**
- **Leader (`<backspace>`):** LazyVim defaults and plugin keymaps
- **Localleader (`<space>`):** Personal minimal workflow

This gives us:
- ✅ Clean separation of concerns
- ✅ No conflicts with LazyVim updates  
- ✅ Complete control over primary workflow
- ✅ LazyVim functionality still accessible but out of the way

## Proposed Solution

### Key Configuration
```lua
-- Put in lua/config/options.lua
vim.g.mapleader = "\b"        -- Backspace for LazyVim defaults  
vim.g.maplocalleader = " "    -- Space for personal clean workflow
```

### Minimal Workflow Structure for `<localleader>` (Space)

#### Core Actions (Single Keys - Most Frequently Used)
```lua
<space>f  -- Find files (git-aware)
<space>s  -- Search/grep text (your smart venv search)
<space>g  -- Git UI (LazyGit)  
<space>t  -- Terminal toggle
<space>b  -- Buffer picker
<space>r  -- Recent files
<space>p  -- Projects picker
```

#### Secondary Groups (Two Keys - Context Specific)

**`<space>d` - Diff/Development**
```lua
<space>dd -- Toggle diffview (auto-detect base)
<space>dp -- Diff picker (search changed files)
<space>dr -- Diff vs specific branch (prompt) 
<space>dc -- Close diffview
```

**`<space>c` - Code (Language-Specific)**  
```lua
<space>cf -- Format
<space>ca -- Code action
<space>cr -- Rename
<space>cd -- Definition
<space>ci -- Implementation
```

**`<space>x` - eXecute/Run**
```lua
<space>xx -- Run current file (language-aware)
<space>xt -- Run tests
<space>xp -- Python REPL  
<space>xr -- Restart LSP
```

**`<space>u` - Utilities/Toggles**
```lua
<space>ul -- Toggle line numbers
<space>uw -- Toggle word wrap
<space>us -- Toggle spell check
<space>up -- Toggle Pyright diagnostic mode
<space>uh -- Toggle inlay hints
```

**`<space>w` - Window Management**
```lua
<space>wh/j/k/l -- Navigate windows
<space>ws -- Split horizontal
<space>wv -- Split vertical  
<space>wc -- Close window
<space>wo -- Only window
```

### Design Principles
1. **Single letters for daily actions** - fastest access
2. **Logical grouping with mnemonics** - easy to remember
3. **Keep under 20 total mappings** - forces prioritization
4. **Context-aware where possible** - smart defaults
5. **Max 2 keystrokes** - no deep nesting

## Implementation Plan

### Phase 1: Leader Key Swap
```lua
-- In lua/config/options.lua (add these lines)
vim.g.mapleader = "\b"        -- Backspace  
vim.g.maplocalleader = " "    -- Space
```

### Phase 2: Create Clean Keymap Module
```lua
-- Create lua/config/my_workflow.lua
local M = {}

M.setup = function()
  -- Core single-key actions
  local map = vim.keymap.set
  local opts = { noremap = true, silent = true }
  
  map("n", "<localleader>f", "<cmd>Snacks.picker.files<cr>", 
      vim.tbl_extend("force", opts, { desc = "Find files" }))
  map("n", "<localleader>s", "<cmd>GrepVenvCurrentOrSelect<cr>", 
      vim.tbl_extend("force", opts, { desc = "Smart search" }))
  map("n", "<localleader>g", "<cmd>LazyGit<cr>", 
      vim.tbl_extend("force", opts, { desc = "Git UI" }))
  -- ... etc for all mappings
  
  -- Register groups with WhichKey
  require("which-key").add({
    { "<localleader>", group = "My Workflow" },
    { "<localleader>d", group = "Diff" },
    { "<localleader>c", group = "Code" },
    { "<localleader>x", group = "Execute" },
    { "<localleader>u", group = "Utilities" },
    { "<localleader>w", group = "Window" },
  })
end

return M
```

### Phase 3: Migration Strategy
1. **Set up leader key swap** in options
2. **Create workflow module** with all mappings
3. **Call setup function** from init.lua
4. **Remove old scattered keymaps** from existing files
5. **Test all functionality** works correctly
6. **Document any LazyVim keymaps** that are still needed

### Phase 4: Integration Points
- **Call from init.lua:** `require('config.my_workflow').setup()`
- **Current custom functions to integrate:**
  - `toggle_diffview()` functions from keymaps.lua:18-48
  - `toggle_pyright_diagnostic_mode()` from keymaps.lua:54-83  
  - `GrepVenvCurrentOrSelect` and `GrepVenvSelectPackage` commands from keymaps.lua:214-233
  - Custom git pickers from `lua/custom/git/pickers.lua`

## Current Custom Functions to Migrate

### Git Diff Functions (keymaps.lua:17-48)
- `<leader>tg` → `<space>dd` (toggle diffview)
- `<leader>tG` → `<space>dr` (toggle diffview with branch prompt)

### Python Functions (keymaps.lua:54-83, 214-233)  
- `<leader>tp` → `<space>up` (toggle pyright diagnostic mode)
- `<leader>ps` → `<space>s` (smart venv grep - MAIN search function)
- `<leader>pS` → `<space>S` (venv package selector)

### Terminal (from floaterm plugin)
- `<leader>tt` → `<space>t` (terminal toggle)

## Benefits of This Approach

1. **Clean muscle memory** - Space is always your workflow, never conflicts
2. **Complete control** - Only the keymaps you choose and design  
3. **Future-proof** - LazyVim updates can't break your workflow
4. **Discoverable** - WhichKey integration shows your clean groups
5. **Minimal** - Forces prioritization of only essential keymaps
6. **Accessible fallback** - LazyVim defaults still available on backspace when needed

## Next Steps When Ready

1. Back up current keymap configuration
2. Implement leader key swap in options.lua
3. Create and populate my_workflow.lua module  
4. Test all functionality works
5. Clean up old scattered keymaps
6. Iterate and refine based on usage patterns

---
*This document captures the complete context for implementing a clean, minimal keymap structure that separates personal workflow (space) from LazyVim defaults (backspace).*