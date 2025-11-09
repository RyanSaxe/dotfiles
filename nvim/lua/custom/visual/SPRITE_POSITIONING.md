# Pokemon Sprite Positioning System

## Overview

This document describes the algorithm and implementation strategy for dynamically positioning pokemon sprites in the Snacks dashboard. The goal is to support different sprite sizes and allow users to position sprites in any of 9 locations within the dashboard pane while maintaining perfect alignment with other dashboard elements (startup time, recent files, etc.).

## Current State

Currently, the dashboard uses hardcoded values:
- **Height**: 21 lines (fixed in `dashboard.lua:356`)
- **Indent**: 10 spaces (fixed in `dashboard.lua:354`)
- **Padding**: 4 spaces for recent files alignment (`POKEMON_PADDING`)

These values are tailored for medium-sized pokemon like snorlax. Large pokemon get cut off, and small pokemon look disproportionate.

## Goals

1. **Detect sprite dimensions** automatically from pokemon-colorscripts output
2. **Auto-size sprites** by adding `-b` flag for small sprites (unless `force_small` is enabled)
3. **Position sprites** in any of 9 locations within the dashboard pane
4. **Maintain alignment** between left pane (files) and right pane (pokemon) elements
5. **Respect configuration** for user preferences on sizing and positioning

---

## Part 1: Sprite Dimension Detection

### Algorithm

Pokemon-colorscripts outputs ANSI-colored text. We can detect dimensions by:

1. **Width**: Count characters per line (excluding ANSI escape codes)
2. **Height**: Count total lines in output

### Implementation

```lua
-- In custom/visual/utils.lua, add new function:

---Detect dimensions of a pokemon sprite
---@param pokemon_name string The name of the pokemon
---@param is_shiny boolean|nil Whether to show shiny variant
---@param form string|nil Optional form name
---@return number|nil width Width in characters
---@return number|nil height Height in lines
function M.detect_sprite_dimensions(pokemon_name, is_shiny, form)
  local cmd = M.build_pokemon_command(pokemon_name, is_shiny, form)

  -- Execute command and capture output
  local handle = io.popen(cmd)
  if not handle then
    return nil, nil
  end

  local output = handle:read("*a")
  handle:close()

  -- Count lines
  local height = 0
  local max_width = 0

  for line in output:gmatch("[^\r\n]+") do
    height = height + 1

    -- Strip ANSI escape codes to get true width
    -- ANSI codes look like: \x1b[38;2;R;G;Bm or \x1b[0m
    local stripped = line:gsub("\x1b%[[0-9;]*m", "")
    local width = vim.fn.strwidth(stripped)

    if width > max_width then
      max_width = width
    end
  end

  return max_width, height
end
```

### Small Sprite Detection

A sprite is considered "small" if:
- **Width < 40 characters** OR
- **Height < 18 lines**

These thresholds are based on typical pokemon-colorscripts output sizes.

### Auto-sizing Logic

```lua
---Determine if sprite should use -b (big) flag
---@param width number Sprite width in characters
---@param height number Sprite height in lines
---@param force_small boolean User preference to keep small sprites
---@return boolean should_use_big True if -b flag should be added
function M.should_use_big_sprite(width, height, force_small)
  -- Respect user preference
  if force_small then
    return false
  end

  -- Use big version for small sprites
  return width < 40 or height < 18
end
```

Update `build_pokemon_command` to accept auto-sizing:
```lua
function M.build_pokemon_command(pokemon_name, is_shiny, form, use_big)
  local cmd = string.format("pokemon-colorscripts -n %s", pokemon_name)

  if is_shiny then
    cmd = cmd .. " --shiny"
  end

  if form and form ~= "" then
    cmd = cmd .. " --form " .. form
  end

  if use_big then
    cmd = cmd .. " -b"
  end

  cmd = cmd .. " --no-title; sleep 0.01"

  return cmd
end
```

---

## Part 2: Positioning System

### Position Grid

The dashboard pane can be divided into a 3x3 grid:

```
┌─────────────────────────┐
│ top-left  │ top-middle  │ top-right   │
│           │             │             │
├───────────┼─────────────┼─────────────┤
│middle-left│middle-middle│middle-right │
│           │             │             │
├───────────┼─────────────┼─────────────┤
│bottom-left│bottom-middle│bottom-right │
│           │             │             │
└─────────────────────────┘
```

### Configuration

Add to `CONFIG` in dashboard.lua:
```lua
CONFIG = {
  pokemon = {
    -- ... existing config ...

    -- Sprite positioning: "top-left", "top-middle", "top-right",
    --                     "middle-left", "middle-middle", "middle-right",
    --                     "bottom-left", "bottom-middle", "bottom-right"
    position = "middle-middle",
  },
}
```

### Dashboard Pane Dimensions

The Snacks dashboard pane dimensions are determined by the terminal size and Snacks configuration. For a typical terminal:
- **Pane width**: Approximately 50-60 characters (half of terminal width for 2-pane layout)
- **Pane height**: Terminal height minus status line, tabs, etc. (typically 40-50 lines)

These can be detected dynamically:
```lua
local pane_width = vim.o.columns / 2  -- Assuming 2-pane layout
local pane_height = vim.o.lines - 5   -- Minus status/tab lines
```

---

## Part 3: Position Calculation

### Vertical Positioning (Height and Padding Top)

The `height` parameter in Snacks dashboard controls how many lines the terminal section occupies. To position vertically:

```lua
---Calculate vertical positioning for sprite
---@param sprite_height number Height of sprite in lines
---@param pane_height number Total available height in pane
---@param position string Position string (e.g., "top-middle", "middle-left")
---@return number section_height Lines to allocate for terminal section
---@return number padding_top Lines of padding before sprite
function M.calculate_vertical_position(sprite_height, pane_height, position)
  -- Extract vertical component from position string
  local vertical = position:match("^([^-]+)")

  -- Calculate section height (sprite + some buffer)
  local section_height = sprite_height + 2  -- +2 for small buffer

  local padding_top = 0

  if vertical == "top" then
    -- No padding at top
    padding_top = 0
  elseif vertical == "middle" then
    -- Center vertically
    local available_space = pane_height - section_height
    padding_top = math.floor(available_space / 2)
  elseif vertical == "bottom" then
    -- Push to bottom
    local available_space = pane_height - section_height
    padding_top = available_space
  end

  -- Ensure padding_top is non-negative
  padding_top = math.max(0, padding_top)

  return section_height, padding_top
end
```

**Note**: The Snacks dashboard terminal section doesn't directly support padding_top. We may need to add empty lines to the terminal command output:
```lua
local padding_cmd = string.format("for i in {1..%d}; do echo; done", padding_top)
cmd = padding_cmd .. " && " .. pokemon_cmd
```

### Horizontal Positioning (Indent)

The `indent` parameter controls horizontal positioning. Calculate it based on sprite width and desired position:

```lua
---Calculate horizontal positioning for sprite
---@param sprite_width number Width of sprite in characters
---@param pane_width number Total available width in pane
---@param position string Position string (e.g., "top-middle", "middle-left")
---@return number indent Spaces to indent from left edge
function M.calculate_horizontal_position(sprite_width, pane_width, position)
  -- Extract horizontal component from position string
  local horizontal = position:match("-(.+)$")

  local indent = 0

  if horizontal == "left" then
    -- Small indent from left edge
    indent = 2
  elseif horizontal == "middle" then
    -- Center horizontally
    local available_space = pane_width - sprite_width
    indent = math.floor(available_space / 2)
  elseif horizontal == "right" then
    -- Align to right edge
    local available_space = pane_width - sprite_width
    indent = available_space - 2  -- -2 for small margin
  end

  -- Ensure indent is non-negative
  indent = math.max(0, indent)

  return indent
end
```

---

## Part 4: Alignment with Other Elements

### Recent Files Section Alignment

The recent files section in pane 1 uses `POKEMON_PADDING` to align with the pokemon in pane 2. This value needs to be dynamically calculated based on:
- Pokemon sprite width
- Pokemon indent
- Pane layout

```lua
---Calculate padding for recent files to align with pokemon
---@param sprite_width number Width of pokemon sprite
---@param pokemon_indent number Indent of pokemon in pane 2
---@param pane_width number Width of each pane
---@return number padding Padding value for recent files section
function M.calculate_file_section_padding(sprite_width, pokemon_indent, pane_width)
  -- The padding should account for the pokemon's position in its pane
  -- This ensures visual alignment across the two panes

  -- If pokemon is left-aligned, use minimal padding
  if pokemon_indent < 10 then
    return 2
  end

  -- If pokemon is centered or right-aligned, increase padding
  -- to maintain visual balance
  local pokemon_center = pokemon_indent + (sprite_width / 2)
  local pane_center = pane_width / 2

  if pokemon_center > pane_center then
    -- Pokemon is right-biased, add padding to files
    return 6
  else
    -- Default padding
    return 4
  end
end
```

### Startup Time Alignment

The startup time section should always be at the top of pane 1. Its positioning is independent of the pokemon positioning, but we need to ensure:
1. It doesn't overlap with pokemon if pokemon is positioned at "top-*"
2. There's visual balance between the two panes

**Current behavior**: Startup time is always at the top of pane 1. This should remain unchanged.

**Future consideration**: If pokemon is at "top-left" or "top-middle", we might want to adjust the startup section spacing, but this is optional.

---

## Part 5: Implementation Checklist

### Phase 1: Dimension Detection (No Layout Changes)
- [ ] Add `detect_sprite_dimensions()` function
- [ ] Add `should_use_big_sprite()` function
- [ ] Update `build_pokemon_command()` to support `use_big` parameter
- [ ] Test dimension detection with various pokemon (small, medium, large)

### Phase 2: Configuration
- [ ] Add `position` field to CONFIG.pokemon
- [ ] Document all 9 position options in comments
- [ ] Add validation for position string

### Phase 3: Position Calculations
- [ ] Implement `calculate_vertical_position()`
- [ ] Implement `calculate_horizontal_position()`
- [ ] Implement `calculate_file_section_padding()`
- [ ] Add helper to parse position strings

### Phase 4: Dashboard Integration
- [ ] Detect pane dimensions dynamically
- [ ] Calculate pokemon positioning based on CONFIG.pokemon.position
- [ ] Update terminal section configuration with calculated values
- [ ] Update POKEMON_PADDING based on pokemon position
- [ ] Handle padding_top via command prefix (empty lines)

### Phase 5: Testing
- [ ] Test all 9 positions with snorlax (medium sprite)
- [ ] Test with small pokemon (e.g., pichu) without and with -b flag
- [ ] Test with large pokemon (e.g., wailord, eternatus)
- [ ] Test with `force_small = true` configuration
- [ ] Verify alignment of recent files section across all positions
- [ ] Test on different terminal sizes

---

## Part 6: Edge Cases and Considerations

### Very Large Sprites
If a sprite is larger than the available pane space:
- **Width overflow**: Reduce indent to 0, allow sprite to be clipped on right
- **Height overflow**: Use full pane_height, allow bottom to be clipped

```lua
-- In vertical calculation:
if sprite_height > pane_height then
  section_height = pane_height
  padding_top = 0
end

-- In horizontal calculation:
if sprite_width > pane_width then
  indent = 0  -- Align to left, allow clipping
end
```

### Single-Pane Layout
When the terminal width is too small, Snacks might switch to a single-pane layout:
- Pokemon should not be shown (or shown separately)
- Check `utils.show_if_has_second_pane()` before applying pokemon positioning

### Responsive Resizing
Terminal resizes during Neovim session:
- Snacks dashboard likely refreshes on window resize
- Position calculations should be done at render time, not init time
- Consider adding autocmd for VimResized event to recalculate

### Form-Specific Sizing
Some pokemon forms are significantly different sizes:
- Eternatus-eternamax (extremely tall)
- Wailord (very wide)
- Regional forms might have different proportions

The auto-sizing logic should handle these automatically based on detected dimensions.

---

## Part 7: Example Usage

After implementation, users can configure pokemon positioning like this:

```lua
-- In dashboard.lua CONFIG section:
CONFIG = {
  pokemon = {
    name = "charizard",
    is_shiny = false,
    form = "mega-x",
    force_small = false,      -- Auto-size to -b if sprite is small
    position = "bottom-right", -- Place sprite in bottom-right corner
  },
}
```

The system will:
1. Detect charizard-mega-x sprite is 45 characters wide by 25 lines tall
2. Determine it doesn't need -b flag (not small)
3. Calculate indent for right alignment: `pane_width - 45 - 2 = indent`
4. Calculate section_height: 25 + 2 = 27 lines
5. Calculate padding_top for bottom alignment: `pane_height - 27 = padding_top`
6. Apply these values to the dashboard terminal section
7. Adjust POKEMON_PADDING for recent files to maintain visual balance

---

## Summary

This sprite positioning system provides:
- ✅ Automatic sprite dimension detection
- ✅ Smart auto-sizing with `-b` flag for small sprites
- ✅ 9-position grid system for flexible placement
- ✅ Maintained alignment between dashboard elements
- ✅ Respect for user preferences (force_small, position)
- ✅ Graceful handling of edge cases (overflow, resize, single-pane)

The implementation should be done in phases, starting with dimension detection and building up to full positioning support.
