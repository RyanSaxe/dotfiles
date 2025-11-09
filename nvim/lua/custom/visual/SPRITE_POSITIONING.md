# Pokemon Sprite Positioning System

## Overview

This document describes the algorithm and implementation strategy for dynamically positioning pokemon sprites in the Snacks dashboard. The goal is to support different sprite sizes and allow users to position sprites in any of 9 locations within the dashboard pane while maintaining perfect alignment with other dashboard elements.

**Key Innovation**: The system ensures both dashboard panes have exactly the same total height by calculating the height of all sections in pane 1, then creating a pokemon section in pane 2 that matches that total height. Pokemon positioning (top/middle/bottom) determines where within that fixed-height section the sprite appears.

---

## Current Architecture Analysis

### How dashboard.lua Currently Works

The current dashboard implementation has these characteristics:

1. **Module-level command building** (line 121): `POKEMON_CMD` is built once at module init time with static parameters
2. **Static padding constant** (line 124): `POKEMON_PADDING = 4` is hardcoded for aligning recent files
3. **Section functions return arrays**: Functions like `search_keys()`, `globalkeys()`, and `get_recent_files()` return section arrays directly
4. **No height tracking**: Sections don't know or report their own heights
5. **Hardcoded terminal section dimensions** (lines 426-428):
   - `height = 21` (lines for pokemon sprite)
   - `indent = 10` (horizontal position)
   - `padding = 0` (vertical offset)

### Problems with Current Approach

- Hardcoded values only work well for medium-sized pokemon (like snorlax)
- Large pokemon get clipped/cut off
- Small pokemon look disproportionate with too much empty space
- Panes may have different total heights, creating visual imbalance
- No flexibility for user to position sprites
- Manual trial-and-error required to adjust POKEMON_PADDING

---

## Proposed Architecture Changes

### Core Pattern: Sections Return Height

**New Requirement**: All section-building functions must return BOTH their sections AND the total height those sections occupy.

```lua
-- OLD PATTERN:
function search_keys()
  local sections = { ... }
  return sections
end

-- NEW PATTERN:
function search_keys()
  local sections = { ... }
  local height = 8  -- 1 (header) + 5 (keys) + 2 (padding)
  return sections, height
end
```

NOTE: if the section is marked with enabled=false, then of course height should be outputted as 0, this way we dont need to worry about that downstream.

### Benefits

This enables:

- **Dynamic pane height calculation**: Sum up all section heights to get total pane height
- **Perfect pane-to-pane alignment**: Make pokemon pane exactly match the other pane's height
- **Flexible pokemon positioning**: Position sprite within a fixed-height section that matches the opposite pane
- **Automatic adjustment**: As sections change (git sections appear/disappear), heights automatically recalculate

### Implementation in create_sections()

```lua
function M.create_sections()
  -- Build pane 1 sections and track heights
  local search_sections, search_height = search_keys()
  local files_sections, files_height = get_recent_files()
  local global_sections, global_height = globalkeys()
  local git_sections, git_height = git_sections_if_in_repo()  -- Returns 0 height if not in git

  -- Calculate total height of pane 1
  local pane1_total_height = search_height + files_height + global_height + git_height

  -- Create pokemon section with matching height
  local pokemon_sections, pokemon_height = create_pokemon_section(pane1_total_height)

  -- Combine all sections
  return {
    search_sections,
    files_sections,
    git_sections,      -- Might be empty/disabled
    global_sections,
    pokemon_sections,
  }
end
```

---

## Goals

1. **Detect sprite dimensions** automatically from pokemon-colorscripts output using two-pass approach
2. **Auto-size sprites** by adding `-b` flag for small sprites (unless `force_small` is enabled)
3. **Match pane heights** by calculating total height of non-pokemon pane and matching it with pokemon section
4. **Position sprites** within fixed-height section in any of 9 locations (3x3 grid)
5. **Maintain alignment** by ensuring both panes have identical total heights
6. **Respect configuration** for user preferences on sizing and positioning

---

## Configuration System

The sprite positioning system follows the CONFIG pattern established in the dashboard (similar to `CONFIG.colors` and `CONFIG.pokemon`). Users configure positioning through a simple declarative interface:

```lua
CONFIG = {
  pokemon = {
    name = "charizard",
    is_shiny = false,
    form = "mega-x",

    -- Keep small sprites small (don't add -b flag)
    -- This is an aesthetic preference, not a functionality requirement
    force_small = false,

    -- Position within the pokemon section: "top-left", "middle-middle", "bottom-right", etc.
    -- Default: "middle-middle"
    position = "middle-middle",
  },
  colors = {
    -- Existing color configuration...
  },
}
```

### Position Grid

The pokemon section uses a 3x3 grid positioning system:

```
┌───────────────────────────────────────┐
│ top-left    │ top-middle    │ top-right    │
│             │               │              │
├─────────────┼───────────────┼──────────────┤
│ middle-left │ middle-middle │ middle-right │  ← default
│             │               │              │
├─────────────┼───────────────┼──────────────┤
│ bottom-left │ bottom-middle │ bottom-right │
│             │               │              │
└───────────────────────────────────────┘
```

Valid position values:

- `"top-left"`, `"top-middle"`, `"top-right"`
- `"middle-left"`, `"middle-middle"`, `"middle-right"`
- `"bottom-left"`, `"bottom-middle"`, `"bottom-right"`

Default if not specified: `"middle-middle"`

Some extra notes:

1. for all non-middle specifications (e.g. top, bottom, left, right), this is specifically saying "the [given orientation] most pixel should touch that edge". So the bottom most pixel of the sprite should obviously be as low as it physically can be in the section. Same goes for left, right, top. Note, for things like top-left, this means you will need to of course take that into account to try and hit both edges. make sure the sprite NEVER overflows unless it literally cannot fit into the box to begin with, in which case use vim.notify to tell the user that.
2. when middle-middle is selected, since there is no required edge to hit, try and perfectly center the sprite.


### Zero-Configuration Auto-Detection

The system automatically detects all necessary dimensions at runtime:

- ✅ **Sprite dimensions** - Width and height parsed from pokemon-colorscripts output (two-pass detection)
- ✅ **Terminal size** - Accessed via `vim.o.columns` and `vim.o.lines`
- ✅ **Dashboard pane dimensions** - Detected from `Snacks.config.dashboard.width` and `.pane_gap`
- ✅ **Section heights** - Calculated by section-building functions and accumulated

**No manual configuration needed!** The system respects any customizations users make to their Snacks dashboard configuration.

### Performance

Sprite dimension detection adds approximately **20-100ms** to dashboard startup time:

- Two-pass detection: Run without -b (~10ms), determine sizing, run with -b if needed (~10ms)
- Command execution and parsing: ~10-50ms per pass
- Height calculation: <1ms (negligible)

This is acceptable compared to typical dashboard startup (100-300ms total).

however, because of the time added to start time here, what you should actually do is encorporate sprite dimensions into the data structure!! This way there does not need to be repeatable calculations once a user knows what they are asking for.

---

## Part 1: Sprite Dimension Detection

### Two-Pass Detection Approach

To accurately detect sprite dimensions while supporting auto-sizing, we use a two-pass approach:

**Pass 1**: Detect dimensions without `-b` flag

1. Build base pokemon command (no -b flag)
2. Execute and parse output
3. Determine sprite width and height
4. Check if sprite is "small" (width < 40 OR height < 18)

**Pass 2**: Rebuild and re-detect if needed

1. If sprite is small AND `force_small = false`, add `-b` flag
2. Rebuild command with -b
3. Execute and parse output again
4. Get FINAL dimensions (larger sprite)
5. Use these final dimensions for all positioning calculations

**Rationale**:

- Small sprites need -b flag for better appearance
- But -b changes the dimensions
- We need final dimensions for accurate positioning
- Two passes ensure we position based on what will actually render

### Algorithm

Pokemon-colorscripts outputs ANSI-colored text. We detect dimensions by:

1. **Width**: Count characters per line (excluding ANSI escape codes)
2. **Height**: Count total lines in output

### Implementation

```lua
-- In custom/visual/utils.lua, add new function:

---Detect dimensions of a pokemon sprite
---@param pokemon_name string The name of the pokemon
---@param is_shiny boolean|nil Whether to show shiny variant
---@param form string|nil Optional form name
---@param use_big boolean|nil Whether to use -b flag for detection
---@return number|nil width Width in characters
---@return number|nil height Height in lines
function M.detect_sprite_dimensions(pokemon_name, is_shiny, form, use_big)
  local cmd = M.build_pokemon_command(pokemon_name, is_shiny, form, use_big)

  -- Execute command and capture output
  local handle = io.popen(cmd)
  if not handle then
    vim.notify("Failed to execute pokemon command for dimension detection", vim.log.levels.ERROR)
    return nil, nil
  end

  local output = handle:read("*a")
  handle:close()

  -- Count lines and measure width
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

call pokemon colorscripts on snorlax, as that is like "the nice normal size I like". So lets define small as something some percentage smaller than that? like the size of charmeleon is CLEARLY small. So look at those sizes for an example.

Regardless though ... we should also let users pass -b directly too if they want.

### Two-Pass Detection with Auto-Sizing

```lua
---Detect sprite dimensions with two-pass auto-sizing
---@param pokemon_name string The name of the pokemon
---@param is_shiny boolean|nil Whether to show shiny variant
---@param form string|nil Optional form name
---@param force_small boolean User preference to keep small sprites small
---@return number|nil width Final sprite width
---@return number|nil height Final sprite height
---@return boolean use_big Whether -b flag should be used
function M.detect_sprite_dimensions_auto(pokemon_name, is_shiny, form, force_small)
  -- Pass 1: Detect without -b flag
  local width, height = M.detect_sprite_dimensions(pokemon_name, is_shiny, form, false)

  if not width or not height then
    return nil, nil, false
  end

  -- Determine if sprite is small
  local is_small = width < 40 or height < 18

  -- Check if we should use big version
  local use_big = is_small and not force_small

  -- Pass 2: Re-detect with -b if needed
  if use_big then
    local big_width, big_height = M.detect_sprite_dimensions(pokemon_name, is_shiny, form, true)
    if big_width and big_height then
      return big_width, big_height, true
    else
      -- Fallback to small version if -b detection failed
      return width, height, false
    end
  end

  -- No need for -b, return original dimensions
  return width, height, false
end
```

### Update build_pokemon_command

Update the command builder to support the `use_big` parameter:

```lua
---Build command string for pokemon-colorscripts
---@param pokemon_name string The name of the pokemon
---@param is_shiny boolean|nil Whether to show shiny variant
---@param form string|nil Optional form name
---@param use_big boolean|nil Whether to add -b flag
---@return string command The command string to execute
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

### Performance Considerations

The two-pass detection adds ~20-100ms to startup time:

- **Pass 1**: ~10-50ms (execute command, parse output)
- **Pass 2**: ~10-50ms (only if sprite is small and force_small is false)
- **Total**: Most pokemon won't need pass 2, so typical cost is ~10-50ms

This is acceptable because:

1. One-time cost during dashboard initialization
2. Terminal section is cached by Snacks
3. Adds <20% to typical dashboard startup time
4. Benefit of proper sizing and positioning far outweighs cost

---

## Part 2: Pane Height Matching System

### Core Concept

To ensure visual balance, both dashboard panes must have **exactly the same total height**. This is achieved by:

1. **Calculating pane 1 height**: Sum the heights of all sections in the non-pokemon pane
2. **Creating fixed-height pokemon section**: Make the pokemon section's total height equal to pane 1's total height
3. **Positioning within section**: Use padding to position the sprite within that fixed-height section

### Dashboard Pane Dimensions

The Snacks dashboard pane dimensions are automatically detected at runtime:

#### Pane Width Detection

```lua
-- Detect pane width from Snacks configuration (respects user customizations)
local pane_width = Snacks.config.dashboard.width or 60
local pane_gap = Snacks.config.dashboard.pane_gap or 4
```

**Benefits:**

- Respects any user customizations to Snacks dashboard config
- No assumptions or hardcoded defaults needed
- Automatically stays in sync with dashboard layout

#### Pane Height Detection

```lua
-- Calculate available pane height (minus statusline, tabline, etc.)
-- This is approximate and may need adjustment based on user's UI configuration
local pane_height = vim.o.lines - 5
```

**Note**: The `-5` accounts for typical UI elements (statusline, tabline, cmdline, margins). This provides a good default for most setups and can be adjusted during implementation if needed.

### Section Height Calculation

Each section-building function must calculate and return its total height:

```lua
---Calculate height of a section array
---Each section in the array contributes to total height based on:
--- - 1 line if it's a header/title
--- - 1 line if it's a key entry
--- - N lines if it's a terminal section with height=N
--- - padding value if section has padding field
---@param sections table Array of section configs
---@return number total_height Total lines occupied by all sections
local function calculate_section_height(sections)
  local total = 0
  for _, section in ipairs(sections) do
    -- Add main content height
    if section.section == "terminal" then
      total = total + (section.height or 1)
    elseif section.title or section.desc or section.key then
      total = total + 1
    end

    -- Add padding
    if section.padding then
      total = total + section.padding
    end
  end
  return total
end
```

### Refactoring Section Functions

All section-building functions need to be refactored to return height:

#### Example: search_keys()

```lua
-- Create search keys section for project operations
local function search_keys()
  local cwd = vim.fn.getcwd()
  local project = vim.fn.fnamemodify(cwd, ":t")
  local header = { pane = 1, title = utils.create_aligned_title("Project", project) }

  local keys = {
    { key = "/", desc = "Grep Text", action = ":lua Snacks.dashboard.pick('live_grep')" },
    -- ... more keys ...
  }

  local sections = utils.create_pane(header, keys, 2)

  -- Calculate height: 1 (header) + N (keys) + 2 (padding)
  local height = 1 + #keys + 2

  return sections, height
end
```

#### Example: get_recent_files()

```lua
-- Get recent files for the dashboard
local function get_recent_files()
  local out = {}
  local max_files = 5
  local recent_files = utils.recent_files_in_cwd(max_files)
  local n_files = #recent_files
  local pane = Snacks.git.get_root() and 2 or 1

  -- Build section entries
  for i, rel in ipairs(recent_files) do
    out[#out + 1] = {
      pane = pane,
      indent = 0,
      padding = (i == n_files) and 2 or 0,  -- Padding only on last entry
      desc = utils.normalize_path(rel),
      key = tostring(i),
      action = function() vim.cmd("edit " .. rel) end,
      enabled = recent_project_toggle,
    }
  end

  if #out == 0 then
    out[1] = {
      pane = pane,
      indent = 0,
      padding = 2,
      enabled = recent_project_toggle,
    }
  end

  -- Calculate height: title (2 lines with padding) + files + final padding
  local height = 2 + n_files + 2

  return out, height
end
```

### Helper: utils.create_pane()

Update the utility function to calculate height:

```lua
---Create a pane section with header and keys
---@param header table Header section config
---@param keys table Array of key entries
---@param padding number Padding to add after last entry
---@return table sections Array of section configs
---@return number height Total height of sections
function utils.create_pane(header, keys, padding)
  local sections = { header }

  for i, key in ipairs(keys) do
    local entry = vim.tbl_extend("force", key, {
      pane = header.pane,
      indent = 0,
      padding = (i == #keys) and padding or 0,
    })
    table.insert(sections, entry)
  end

  -- Height: 1 (header) + N (keys) + padding (on last entry)
  local height = 1 + #keys + padding

  return sections, height
end
```

### Accumulating Pane 1 Height

In `create_sections()`, accumulate all section heights:

```lua
function M.create_sections()
  -- Get base branch for git section
  local base_branch = git_utils.get_base_branch()
  local current_branch = git_utils.get_current_branch()
  local in_git = Snacks.git.get_root() ~= nil

  -- Build pane 1 sections and track heights
  local pane1_height = 0

  local search_sections, search_height = search_keys()
  pane1_height = pane1_height + search_height

  local files_sections, files_height = get_recent_files()
  pane1_height = pane1_height + files_height

  local git_sections, git_height = create_git_sections(base_branch, current_branch)
  if in_git then
    pane1_height = pane1_height + git_height
  end

  local global_sections, global_height = globalkeys()
  pane1_height = pane1_height + global_height

  -- Add time section (1 line)
  pane1_height = pane1_height + 1

  -- Create pokemon section with matching height
  local pokemon_sections = create_pokemon_section(pane1_height)

  -- Combine all sections
  return {
    search_sections,
    files_sections,
    git_sections,
    global_sections,
    {
      pane = 1,
      title = utils.create_aligned_title("Time", os.date("%H:%M")),
      indent = 0,
    },
    pokemon_sections,
  }
end
```

---

## Part 3: Pokemon Section Creation

### Fixed-Height Section with Internal Positioning

The pokemon section has a **fixed total height** matching pane 1. The sprite position (top/middle/bottom) determines where within that section the sprite appears using padding.

```lua
---Create pokemon section with fixed height matching other pane
---@param target_height number Total height this section must occupy
---@return table sections Pokemon section configuration
function create_pokemon_section(target_height)
  local sprite_width, sprite_height, use_big = visual_utils.detect_sprite_dimensions_auto(
    pokemon_name,
    pokemon_shiny,
    pokemon_form,
    CONFIG.pokemon.force_small
  )

  if not sprite_width or not sprite_height then
    -- Dimension detection failed, return empty section with target height
    return {
      {
        pane = 2,
        padding = target_height,
        enabled = utils.show_if_has_second_pane,
      }
    }
  end

  -- Calculate horizontal position (indent)
  local pane_width = Snacks.config.dashboard.width or 60
  local indent = calculate_horizontal_position(sprite_width, pane_width, CONFIG.pokemon.position)

  -- Calculate vertical position within fixed-height section
  local padding_top, padding_bottom = calculate_vertical_position(
    sprite_height,
    target_height,
    CONFIG.pokemon.position
  )

  -- Build pokemon command with correct -b flag
  local pokemon_cmd = visual_utils.build_pokemon_command(
    pokemon_name,
    pokemon_shiny,
    pokemon_form,
    use_big
  )

  return {
    -- Top padding section
    {
      pane = 2,
      padding = padding_top,
      enabled = utils.show_if_has_second_pane,
    },
    -- Pokemon sprite terminal section
    {
      pane = 2,
      section = "terminal",
      cmd = pokemon_cmd,
      ttl = math.huge,
      indent = indent,
      height = sprite_height,
      enabled = utils.show_if_has_second_pane,
    },
    -- Bottom padding section
    {
      pane = 2,
      padding = padding_bottom,
      enabled = utils.show_if_has_second_pane,
    },
    -- Startup time (appears after pokemon)
    {
      pane = 2,
      title = utils.create_aligned_title("Startup", vim.fn.printf("%.1fms", require("lazy").stats().startuptime)),
      indent = 0,
      enabled = utils.show_if_has_second_pane,
    },
  }
end
```

---

## Part 4: Position Calculation

### Horizontal Positioning (Indent)

Calculate horizontal position based on sprite width, pane width, and desired alignment:

```lua
---Calculate horizontal positioning for sprite
---@param sprite_width number Width of sprite in characters
---@param pane_width number Total available width in pane
---@param position string Position string (e.g., "top-middle", "middle-left")
---@return number indent Spaces to indent from left edge
function calculate_horizontal_position(sprite_width, pane_width, position)
  -- Extract horizontal component from position string
  local horizontal = position:match("-(.+)$")

  -- Validate position
  if not horizontal or not vim.tbl_contains({"left", "middle", "right"}, horizontal) then
    vim.notify(
      string.format("Invalid position '%s', using middle", position),
      vim.log.levels.WARN
    )
    horizontal = "middle"
  end

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

  -- Handle overflow: if sprite is wider than pane, just left-align
  if sprite_width > pane_width then
    indent = 0
  end

  return indent
end
```

### Vertical Positioning (Padding Within Fixed-Height Section)

Calculate padding to position sprite within the fixed-height pokemon section:

```lua
---Calculate vertical positioning for sprite within fixed-height section
---@param sprite_height number Height of sprite in lines
---@param section_height number Total height of pokemon section (fixed, matches pane 1)
---@param position string Position string (e.g., "top-middle", "middle-left")
---@return number padding_top Lines of padding before sprite
---@return number padding_bottom Lines of padding after sprite
function calculate_vertical_position(sprite_height, section_height, position)
  -- Extract vertical component from position string
  local vertical = position:match("^([^-]+)")

  -- Validate position
  if not vertical or not vim.tbl_contains({"top", "middle", "bottom"}, vertical) then
    vim.notify(
      string.format("Invalid position '%s', using middle", position),
      vim.log.levels.WARN
    )
    vertical = "middle"
  end

  -- Calculate available space around sprite
  local available_space = section_height - sprite_height

  -- Handle overflow: if sprite is taller than section, allocate all to sprite
  if available_space < 0 then
    return 0, 0
  end

  local padding_top = 0
  local padding_bottom = 0

  if vertical == "top" then
    -- No padding at top, all padding at bottom
    padding_top = 0
    padding_bottom = available_space
  elseif vertical == "middle" then
    -- Center vertically, split padding evenly
    padding_top = math.floor(available_space / 2)
    padding_bottom = available_space - padding_top
  elseif vertical == "bottom" then
    -- All padding at top, no padding at bottom
    padding_top = available_space
    padding_bottom = 0
  end

  return padding_top, padding_bottom
end
```

### Position Validation

Add a helper to validate position strings:

```lua
---Validate and normalize position string
---@param position string|nil Position string to validate
---@return string normalized Valid position string
function validate_position(position)
  local valid_positions = {
    "top-left", "top-middle", "top-right",
    "middle-left", "middle-middle", "middle-right",
    "bottom-left", "bottom-middle", "bottom-right",
  }

  -- Default position
  if not position or position == "" then
    return "middle-middle"
  end

  -- Check if valid
  if vim.tbl_contains(valid_positions, position) then
    return position
  end

  -- Invalid, use default and warn
  vim.notify(
    string.format("Invalid pokemon position '%s', using 'middle-middle'", position),
    vim.log.levels.WARN
  )
  return "middle-middle"
end
```

---

## Part 5: Implementation Checklist

### Phase 0: Architecture Refactoring

- [ ] Update `utils.create_pane()` to calculate and return height
- [ ] Refactor `search_keys()` to return `sections, height`
- [ ] Refactor `globalkeys()` to return `sections, height`
- [ ] Refactor `get_recent_files()` to return `sections, height`
- [ ] Create helper function to build git sections and return height
- [ ] Add `calculate_section_height()` helper if needed
- [ ] Test that all refactored functions return correct heights

### Phase 1: Dimension Detection (Two-Pass)

- [ ] Add `detect_sprite_dimensions()` function with `use_big` parameter
- [ ] Add `detect_sprite_dimensions_auto()` function implementing two-pass logic
- [ ] Update `build_pokemon_command()` to support `use_big` parameter
- [ ] Test dimension detection with various pokemon:
  - Small pokemon (pichu, joltik) without and with -b flag
  - Medium pokemon (snorlax, charizard)
  - Large pokemon (wailord, eternatus)

### Phase 2: Configuration

- [ ] Add `position` field to `CONFIG.pokemon` in dashboard.lua
- [ ] Set default position to "middle-middle"
- [ ] Document all 9 position options in comments
- [ ] Add `validate_position()` function
- [ ] Test position validation with valid and invalid inputs

### Phase 3: Pane Height Calculation

- [ ] Modify `create_sections()` to accumulate pane 1 heights
- [ ] Call all section functions and sum their returned heights
- [ ] Handle conditional sections (git sections only if in repo)
- [ ] Test height calculation in different scenarios:
  - In git repo vs. not in git repo
  - With different numbers of recent files
  - After configuration changes

### Phase 4: Position Calculation

- [ ] Implement `calculate_horizontal_position()` function
- [ ] Implement `calculate_vertical_position()` function
- [ ] Test position calculations with edge cases:
  - Sprite wider than pane width
  - Sprite taller than section height
  - Very small sprites
  - Each of the 9 positions

### Phase 5: Pokemon Section Creation

- [ ] Create `create_pokemon_section()` function
- [ ] Integrate dimension detection (two-pass)
- [ ] Integrate position calculation (horizontal + vertical)
- [ ] Build pokemon command with correct -b flag
- [ ] Create section array with padding sections
- [ ] Test pokemon section creation with various configurations

### Phase 6: Dashboard Integration

- [ ] Update `create_sections()` to use new pokemon section creation
- [ ] Remove old `POKEMON_CMD` module-level variable
- [ ] Remove old `POKEMON_PADDING` constant
- [ ] Update color application to still work (should be unaffected)
- [ ] Test full dashboard rendering

### Phase 7: Testing

- [ ] Test all 9 positions with medium sprite (snorlax)
- [ ] Test small pokemon (pichu) with `force_small = false` (should use -b)
- [ ] Test small pokemon (pichu) with `force_small = true` (should stay small)
- [ ] Test large pokemon (wailord, eternatus)
- [ ] Test in git repo (pane 2 should match pane 1 height)
- [ ] Test not in git repo (pokemon might be in pane 1)
- [ ] Test on different terminal sizes
- [ ] Test with different Snacks dashboard widths
- [ ] Verify startup time is acceptable (~20-100ms overhead)

### Phase 8: Error Handling

- [ ] Handle dimension detection failures gracefully
- [ ] Handle command execution failures
- [ ] Handle invalid position strings
- [ ] Handle sprite overflow cases
- [ ] Add appropriate error messages and fallbacks

---

## Part 6: Edge Cases and Considerations

### Very Large Sprites

If a sprite is larger than the available space:

**Width overflow**:

```lua
if sprite_width > pane_width then
  indent = 0  -- Left-align, allow right side to be clipped
end
```

**Height overflow**:

```lua
if sprite_height > section_height then
  -- Use sprite height as section height, no padding
  padding_top = 0
  padding_bottom = 0
  -- Terminal section will clip at bottom if needed
end
```

### Single-Pane Layout

When the terminal width is too small, Snacks might switch to a single-pane layout:

- Check `utils.show_if_has_second_pane()` before creating pokemon section
- Pokemon section should be disabled if only one pane is shown
- This is already handled by the `enabled` field in section configs

### Responsive Resizing

Terminal resizes during Neovim session:

- Snacks dashboard likely refreshes on window resize
- Position calculations are done in `create_sections()` at render time
- Each render recalculates dimensions and positions dynamically
- May want to add autocmd for `VimResized` event if needed

### Form-Specific Sizing

Some pokemon forms have significantly different sizes:

- Eternatus-eternamax (extremely tall)
- Wailord (very wide)
- Regional forms might have different proportions

The auto-sizing logic handles these automatically based on detected dimensions.

### Dimension Detection Failures

If dimension detection fails (command error, no output, etc.):

```lua
if not sprite_width or not sprite_height then
  -- Return empty section with target height to maintain pane balance
  return {
    {
      pane = 2,
      padding = target_height,
      enabled = utils.show_if_has_second_pane,
    }
  }
end
```

### Position String Variations

Handle common user errors:

- Missing position → default to "middle-middle"
- Invalid format (e.g., "top", "left", "topleft") → default to "middle-middle" with warning
- Typos (e.g., "midle-middle") → default to "middle-middle" with warning

Use `validate_position()` function to normalize inputs.

---

## Part 7: Example Usage

After implementation, users can configure pokemon positioning through the CONFIG system:

### Basic Example

```lua
-- In dashboard.lua CONFIG section:
CONFIG = {
  pokemon = {
    name = "charizard",
    is_shiny = false,
    form = "mega-x",
    force_small = false,       -- Auto-size to -b if sprite is small
    position = "bottom-right", -- Place sprite in bottom-right corner
  },
  colors = {
    background_mode = "dark",
    title_source = "auto",     -- Use colors from sprite
    key_source = "auto",
    desc_source = "Comment",
  },
}
```

### Different Positioning Examples

```lua
-- Center the pokemon (default)
CONFIG = {
  pokemon = {
    name = "snorlax",
    position = "middle-middle",
  },
}

-- Top-right corner for a decorative effect
CONFIG = {
  pokemon = {
    name = "pikachu",
    is_shiny = true,
    position = "top-right",
  },
}

-- Bottom-left for a grounded appearance
CONFIG = {
  pokemon = {
    name = "gengar",
    position = "bottom-left",
  },
}

-- Keep small sprites small (disable auto-sizing)
CONFIG = {
  pokemon = {
    name = "pichu",
    force_small = true,        -- Don't add -b flag
    position = "middle-right",
  },
}
```

### How It Works: Complete Flow

When the dashboard initializes with `position = "bottom-right"` and `name = "charizard"`:

#### Step 1: Build Pane 1 and Calculate Height

```lua
-- In create_sections():
local search_sections, search_height = search_keys()        -- Returns 8 lines
local files_sections, files_height = get_recent_files()     -- Returns 9 lines
local git_sections, git_height = create_git_sections()      -- Returns 15 lines (if in git)
local global_sections, global_height = globalkeys()         -- Returns 7 lines

local pane1_total_height = search_height + files_height + git_height + global_height + 1
-- Result: 8 + 9 + 15 + 7 + 1 = 40 lines
```

#### Step 2: Detect Sprite Dimensions (Two-Pass)

```lua
-- Pass 1: Detect without -b
local width, height = detect_sprite_dimensions("charizard", false, "mega-x", false)
-- Result: width = 45, height = 25

-- Check if small
local is_small = (width < 40) or (height < 18)
-- Result: is_small = false (45 >= 40 and 25 >= 18)

-- Determine if -b needed
local use_big = is_small and not CONFIG.pokemon.force_small
-- Result: use_big = false

-- No pass 2 needed, final dimensions: width = 45, height = 25
```

#### Step 3: Calculate Horizontal Position

```lua
local indent = calculate_horizontal_position(45, 60, "bottom-right")
-- Extract "right" from position
-- Calculate: indent = 60 - 45 - 2 = 13
-- Result: indent = 13 (right-aligned with small margin)
```

#### Step 4: Calculate Vertical Position

```lua
local padding_top, padding_bottom = calculate_vertical_position(25, 40, "bottom-right")
-- Extract "bottom" from position
-- Available space: 40 - 25 = 15
-- For bottom: padding_top = 15, padding_bottom = 0
-- Result: padding_top = 15, padding_bottom = 0
```

#### Step 5: Build Pokemon Section

```lua
local pokemon_sections = {
  { pane = 2, padding = 15 },                    -- Top padding: 15 lines
  {
    pane = 2,
    section = "terminal",
    cmd = "pokemon-colorscripts -n charizard --form mega-x --no-title; sleep 0.01",
    height = 25,                                 -- Sprite: 25 lines
    indent = 13,
  },
  { pane = 2, padding = 0 },                     -- Bottom padding: 0 lines
  { pane = 2, title = "Startup: 123.4ms" },      -- Startup time: 1 line (implicit)
}
-- Total pokemon pane height: 15 + 25 + 0 + 1 = 41 lines (matches pane 1!)
```

#### Step 6: Result

- Charizard Mega X sprite appears in bottom-right corner of pane 2
- Sprite is positioned at the bottom (15 lines of padding above it)
- Sprite is right-aligned (indent of 13 pushes it right)
- Both panes have identical total height (40-41 lines)
- Perfect visual balance across dashboard!

---

## Summary

This sprite positioning system provides:

- ✅ **Zero-configuration auto-detection** - Automatically detects sprite dimensions, terminal size, and Snacks dashboard configuration
- ✅ **Two-pass dimension detection** - Accurately detects final sprite dimensions accounting for -b flag
- ✅ **Smart auto-sizing** - Automatically adds `-b` flag for small sprites (unless disabled)
- ✅ **Pane height matching** - Both panes have exactly the same total height for perfect visual balance
- ✅ **9-position grid system** - Flexible placement via simple `CONFIG.pokemon.position` setting
- ✅ **Fixed-height positioning** - Pokemon positioned within section that matches opposite pane's total height
- ✅ **Section-height architecture** - All section functions return their height for accurate calculation
- ✅ **Dynamic pane detection** - Uses `Snacks.config.dashboard` to respect user customizations
- ✅ **CONFIG-based interface** - Follows established pattern (like CONFIG.colors) for consistency
- ✅ **Graceful edge cases** - Handles overflow, resize, failures, and unusual sprite sizes
- ✅ **Error handling** - Validates inputs and provides helpful fallbacks and warnings

**Key Features:**

- No manual dimension configuration required
- Perfect pane alignment through height matching
- Respects all Snacks dashboard customizations automatically
- Minimal performance impact (~20-100ms startup cost)
- Simple declarative interface for users

The implementation should be done in phases, starting with architecture refactoring, then dimension detection, then position calculation, and finally full integration.
