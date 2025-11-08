# Dynamic Tmux Statusline Color Synchronization with Neovim

## Overview

This document outlines a solution for dynamically synchronizing tmux statusline colors with Neovim colorscheme changes, building upon the existing bg.nvim plugin functionality. When you change your Neovim colorscheme, both Ghostty and tmux's statusline will automatically update to match.

## Current State

### How bg.nvim Works

The bg.nvim plugin (`~/.local/share/nvim/lazy/bg.nvim/`) currently synchronizes terminal colors with Neovim's colorscheme using OSC escape sequences.

#### Core Mechanism

1. **Colorscheme Detection**
```lua
vim.api.nvim_create_autocmd({ "ColorScheme", "UIEnter" }, { callback = update })
```
Hooks into Neovim's ColorScheme autocmd to detect theme changes.

2. **Color Extraction**
```lua
local normal = vim.api.nvim_get_hl_by_name("Normal", true)
local bg = normal["background"]  -- RGB integer
local fg = normal["foreground"]  -- RGB integer
-- Convert to hex: string.format("#%06x", rgb_value)
```

3. **Terminal Communication via OSC Sequences**
   - **OSC 11**: Set background color (`\033]11;<color>\007`)
   - **OSC 12**: Set cursor/foreground color (`\033]12;<color>\007`)

4. **Tmux Support Already Exists!**
```lua
if os.getenv("TMUX") then
    -- Wraps OSC sequences for tmux passthrough
    os.execute('printf "\\ePtmux;\\e\\033]11;' .. bghex .. '\\007\\e\\\\"')
    os.execute('printf "\\ePtmux;\\e\\033]12;' .. fghex .. '\\007\\e\\\\"')
end
```
The `\ePtmux;...\e\\` wrapper allows OSC sequences to pass through tmux to the underlying terminal.

### Current Tmux Configuration

The tmux configuration (`tmux/tmux.conf`) uses hardcoded TokyoNight colors:
```bash
set -g @tokyonight_bg "#1a1b26"
set -g @tokyonight_fg "#c0caf5"
set -g @tokyonight_blue "#7aa2f7"
set -g @tokyonight_cyan "#7dcfff"
# ... etc
```

These static variables are used throughout the statusline configuration but don't update when the terminal colors change.

## The Problem

While bg.nvim successfully updates Ghostty's colors through tmux, several components remain static:

**Tmux statusline** remains static because:
1. Tmux's internal color variables (`@tokyonight_*`) are set once at config load
2. These variables don't automatically sync with terminal color changes
3. The statusline uses these static variables for all its styling

**Lualine** (Neovim statusline/winbar) doesn't update because:
1. The `opts` function in the lazy.nvim plugin spec only runs once at plugin load
2. Color variables (`c` from `tokyonight.colors.setup()`) are captured in closures at that time
3. When colorscheme changes, the functions still reference the stale captured colors
4. Lualine doesn't have built-in refresh behavior for custom themes (only `theme = 'auto'`)
5. **Status**: Lualine color refresh needs investigation - standard ColorScheme autocmd approach did not work

## Proposed Solution

Extend the bg.nvim functionality to also update tmux's internal color variables whenever the Neovim colorscheme changes.

### Architecture

```
Neovim ColorScheme Change
         ↓
    bg.nvim hooks
         ↓
    ┌────┴────┐
    ↓         ↓
OSC Sequences  Tmux Commands
    ↓         ↓
 Ghostty    Tmux Variables
 Updates    Update (@tokyonight_*)
    ↓         ↓
 Terminal   Statusline
 Colors     Colors
```

### Implementation Plan

#### 1. Create Neovim Plugin Extension

Create `nvim/lua/plugins/tmux-colors.lua`:

```lua
return {
  "typicode/bg.nvim",
  lazy = false,
  config = function()
    -- Hook into ColorScheme autocmd alongside bg.nvim
    vim.api.nvim_create_autocmd({ "ColorScheme", "UIEnter" }, {
      callback = function()
        -- Let bg.nvim handle terminal colors first
        vim.defer_fn(function()
          -- Only proceed if we're in tmux
          if not os.getenv("TMUX") then return end

          -- Extract colors from current colorscheme
          local colors = require("plugins.tmux-colors.extractor").extract_colors()

          -- Update tmux variables
          require("plugins.tmux-colors.updater").update_tmux(colors)
        end, 100) -- Small delay to ensure bg.nvim runs first
      end
    })
  end
}
```

#### 2. Color Extraction Module

Create `nvim/lua/plugins/tmux-colors/extractor.lua`:

```lua
local M = {}

function M.extract_colors()
  local colors = {}

  -- Helper to convert vim highlight to hex
  local function hl_to_hex(hl_name, attr)
    local hl = vim.api.nvim_get_hl_by_name(hl_name, true)
    local value = hl[attr]
    if value then
      return string.format("#%06x", value)
    end
    return nil
  end

  -- Map Neovim highlight groups to tmux color variables
  colors.bg = hl_to_hex("Normal", "background") or "#1a1b26"
  colors.fg = hl_to_hex("Normal", "foreground") or "#c0caf5"
  colors.blue = hl_to_hex("Function", "foreground") or "#7aa2f7"
  colors.cyan = hl_to_hex("Special", "foreground") or "#7dcfff"
  colors.green = hl_to_hex("String", "foreground") or "#9ece6a"
  colors.red = hl_to_hex("Error", "foreground") or "#f7768e"
  colors.yellow = hl_to_hex("Warning", "foreground") or "#e0af68"
  colors.orange = hl_to_hex("Number", "foreground") or "#ff9e64"
  colors.gray = hl_to_hex("Comment", "foreground") or "#565f89"
  colors.dark = hl_to_hex("StatusLine", "background") or "#15161e"
  colors.fg_gutter = hl_to_hex("LineNr", "foreground") or "#3b4261"

  return colors
end

return M
```

#### 3. Tmux Update Module

Create `nvim/lua/plugins/tmux-colors/updater.lua`:

```lua
local M = {}

function M.update_tmux(colors)
  -- Build tmux commands to update color variables
  local commands = {}

  for name, value in pairs(colors) do
    table.insert(commands, string.format(
      "tmux set-option -g @tokyonight_%s '%s'",
      name, value
    ))
  end

  -- Update all colors in one go
  for _, cmd in ipairs(commands) do
    vim.fn.system(cmd)
  end

  -- Refresh tmux status line to apply new colors
  vim.fn.system("tmux refresh-client -S")
end

return M
```

#### 4. Update Tmux Scripts

Modify `tmux/scripts/notification-color.sh` to check for dynamically set variables:

```bash
#!/usr/bin/env bash

# Try to get dynamically set color first, fallback to static
get_color() {
  local color_name=$1
  local fallback=$2
  local dynamic_color=$(tmux show-option -gqv "@tokyonight_$color_name")
  echo "${dynamic_color:-$fallback}"
}

# Check if tmux prefix is currently active
prefix_active=$(tmux display-message -p '#{client_prefix}' 2>/dev/null || echo "0")

# Get notification count
count=$("$count_script")

# Determine color based on conditions
if [[ "$prefix_active" == "1" ]]; then
  echo $(get_color "blue" "#7aa2f7")
elif [[ "$count" -gt 0 ]]; then
  echo $(get_color "orange" "#ff9e64")
else
  echo $(get_color "gray" "#565f89")
fi
```

### Advanced Features

#### Support for Multiple Colorschemes

The extractor can be enhanced to detect the current colorscheme type:

```lua
local function detect_colorscheme_family()
  local colorscheme = vim.g.colors_name

  if colorscheme:match("tokyonight") then
    return "tokyonight"
  elseif colorscheme:match("catppuccin") then
    return "catppuccin"
  elseif colorscheme:match("gruvbox") then
    return "gruvbox"
  -- Add more as needed
  end

  return "default"
end
```

#### Persistent Color Storage

Save colors to a file for tmux server restarts:

```lua
function M.save_colors(colors)
  local config_dir = vim.fn.expand("~/.config/tmux/")
  local color_file = config_dir .. "dynamic-colors.conf"

  local lines = {}
  for name, value in pairs(colors) do
    table.insert(lines, string.format('set -g @tokyonight_%s "%s"', name, value))
  end

  vim.fn.writefile(lines, color_file)

  -- Source in tmux
  vim.fn.system("tmux source-file " .. color_file)
end
```

### Testing Plan

1. **Basic Functionality**
   - Switch between different Neovim colorschemes
   - Verify Ghostty background updates
   - Verify tmux statusline colors update

2. **Edge Cases**
   - Test with nested tmux sessions
   - Test with multiple Neovim instances
   - Test colorschemes without all highlight groups

3. **Performance**
   - Measure update latency
   - Ensure no visible flicker
   - Test with rapid colorscheme switching

### Limitations & Considerations

1. **Color Depth**: Ensure terminal supports true color (24-bit)
2. **Tmux Version**: Requires tmux 2.2+ for proper color support
3. **Performance**: Color extraction and tmux updates add ~100ms latency
4. **Scope**: Only affects the current tmux server, not all sessions

## Future Enhancements

### Integration with UI-Focused Branch

This feature will be part of a larger UI improvement initiative including:
- Per-window theme switching (see `per-window-theme-switching.md`)
- Unified color management system
- Theme preset management
- Quick theme switcher UI

### Potential Extensions

1. **Bidirectional Sync**: Allow tmux theme changes to update Neovim
2. **Theme Profiles**: Save and restore complete theme configurations
3. **Gradient Support**: Support for gradient colors in modern terminals
4. **Animation**: Smooth color transitions between themes
5. **External Tool Integration**: Sync with other tools (bat, fzf, etc.)

## Implementation Checklist

- [ ] Create tmux-colors.lua plugin file
- [ ] Implement color extractor module
- [ ] Implement tmux updater module
- [ ] Update notification-color.sh for dynamic colors
- [ ] **Fix lualine color refresh on colorscheme change**
  - [ ] Investigate why ColorScheme autocmd doesn't trigger lualine refresh
  - [ ] Consider alternative approaches (manual refresh command, different hook, etc.)
  - [ ] Ensure all lualine components (bubbles, winbar, etc.) update properly
- [ ] Test with TokyoNight variations
- [ ] Test with non-TokyoNight themes
- [ ] Add error handling and fallbacks
- [ ] Document user configuration options
- [ ] Create demo/test script

## References

- [bg.nvim Plugin](https://github.com/typicode/bg.nvim)
- [XTerm Control Sequences](https://invisible-island.net/xterm/ctlseqs/ctlseqs.html)
- [Tmux Color Documentation](https://man.openbsd.org/tmux#STYLES)
- [OSC Escape Sequences](https://en.wikipedia.org/wiki/ANSI_escape_code#OSC)
- [Neovim Highlight Groups](https://neovim.io/doc/user/syntax.html#highlight-groups)