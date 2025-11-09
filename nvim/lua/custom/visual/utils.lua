-- Visual utilities for dynamic theming based on terminal output
-- Handles pokemon color extraction and selection

local M = {}

-- Load the pokemon colors database
local pokemon_colors = require("custom.visual.pokemon-colors")

---Get colors for a specific pokemon
---@param pokemon_name string The name of the pokemon
---@param is_shiny boolean|nil Whether this is a shiny variant
---@param form string|nil Optional form name (e.g., "alola")
---@param allow_fallback boolean|nil Whether to fall back to non-shiny/no-form (default: true)
---@return table|nil colors Table with dark/light color variants, or nil if not found
function M.get_pokemon_colors(pokemon_name, is_shiny, form, allow_fallback)
  -- Build the key to look up in the database
  local key = pokemon_name:lower()

  if is_shiny then
    key = key .. "-shiny"
  end

  if form and form ~= "" then
    key = key .. "-" .. form:lower():gsub(" ", "-")
  end

  local data = pokemon_colors[key]

  if not data then
    -- Only try fallbacks if allow_fallback is not explicitly false
    if allow_fallback ~= false then
      -- Fallback: try without form if specified
      if form then
        return M.get_pokemon_colors(pokemon_name, is_shiny, nil, allow_fallback)
      end

      -- Fallback: try without shiny if specified
      if is_shiny then
        return M.get_pokemon_colors(pokemon_name, false, nil, allow_fallback)
      end
    end

    vim.notify(string.format("Pokemon colors not found for: %s", key), vim.log.levels.WARN)
    return nil
  end

  return data
end

---Get colors for current vim background, with optional override
---@param pokemon_data table Pokemon color data from database
---@param background_mode string|nil Optional background mode override: "auto", "light", "dark" (default: "auto")
---@return table|nil colors Table with prominent, bright, and dim colors, or nil if not found
function M.get_colors_for_background(pokemon_data, background_mode)
  if not pokemon_data then
    return nil
  end

  -- Determine which background to use
  local bg
  if background_mode == nil or background_mode == "auto" then
    -- Use vim's background setting
    bg = vim.o.background
  elseif background_mode == "light" or background_mode == "dark" then
    -- Use explicit override
    bg = background_mode
  else
    -- Invalid background_mode, fall back to auto
    vim.notify(
      string.format("Invalid background_mode '%s', falling back to auto", background_mode),
      vim.log.levels.WARN
    )
    bg = vim.o.background
  end

  return pokemon_data[bg] or pokemon_data.dark
end

---Select a random pokemon from the database
---@return string pokemon_name Random pokemon name
---@return boolean is_shiny Whether the selected variant is shiny
---@return string|nil form Optional form name
function M.select_random_pokemon()
  -- Get all keys from the database
  local all_keys = {}
  for key, _ in pairs(pokemon_colors) do
    table.insert(all_keys, key)
  end

  if #all_keys == 0 then
    vim.notify("No pokemon found in database", vim.log.levels.ERROR)
    return "pikachu", false, nil
  end

  -- Seed random with current time
  math.randomseed(os.time())

  -- Select a random key
  local selected_key = all_keys[math.random(#all_keys)]
  local entry = pokemon_colors[selected_key]

  -- First, try to use metadata if available (handles pokemon with natural dashes)
  -- Metadata is included in entries generated after this fix (e.g., "ho-oh", "porygon-z")
  if entry._meta then
    return entry._meta.name, entry._meta.is_shiny, entry._meta.form
  end

  -- Fallback: Parse the key using legacy logic (for backwards compatibility)
  -- This may incorrectly split pokemon names containing dashes (e.g., "ho-oh" -> "ho" + form "oh")
  local name = selected_key
  local is_shiny = false
  local form = nil

  -- Check for -shiny suffix
  if name:match("%-shiny$") then
    is_shiny = true
    name = name:gsub("%-shiny$", "")
  end

  -- Check for form (any remaining hyphenated suffix)
  -- NOTE: This incorrectly treats natural dashes in pokemon names as form separators
  local name_parts = vim.split(name, "-")
  if #name_parts > 1 then
    form = table.concat(name_parts, "-", 2)
    name = name_parts[1]
  end

  return name, is_shiny, form
end

---Get list of all available pokemon from pokemon-colorscripts
---This runs the command and parses output, so it's slow - use sparingly
---@return table pokemon_list List of pokemon names
function M.get_available_pokemon_list()
  local handle = io.popen("pokemon-colorscripts --list 2>/dev/null")
  if not handle then
    vim.notify("Failed to run pokemon-colorscripts --list", vim.log.levels.ERROR)
    return { "pikachu" } -- Fallback
  end

  local result = handle:read("*a")
  handle:close()

  -- Parse the output (one pokemon per line)
  local pokemon_list = {}
  for line in result:gmatch("[^\r\n]+") do
    local name = line:match("^%s*(.-)%s*$") -- Trim whitespace
    if name and name ~= "" then
      table.insert(pokemon_list, name)
    end
  end

  if #pokemon_list == 0 then
    vim.notify("No pokemon found from pokemon-colorscripts --list", vim.log.levels.WARN)
    return { "pikachu" } -- Fallback
  end

  return pokemon_list
end

---Select a random pokemon from the full available list (not just database)
---This is slower as it runs pokemon-colorscripts --list
---@return string pokemon_name Random pokemon name
function M.select_random_available_pokemon()
  local pokemon_list = M.get_available_pokemon_list()

  -- Seed random with current time
  math.randomseed(os.time())

  return pokemon_list[math.random(#pokemon_list)]
end

---Build command array for pokemon-colorscripts
---@param pokemon_name string The name of the pokemon
---@param is_shiny boolean|nil Whether to show shiny variant
---@param form string|nil Optional form name
---@return string command The command string to execute
function M.build_pokemon_command(pokemon_name, is_shiny, form)
  local cmd = string.format("pokemon-colorscripts -n %s", pokemon_name)

  if is_shiny then
    cmd = cmd .. " --shiny"
  end

  if form and form ~= "" then
    cmd = cmd .. " --form " .. form
  end

  cmd = cmd .. " --no-title; sleep 0.01"

  return cmd
end

---Resolve a color value from various sources and apply adjustments
---@param value string Color source: 'auto', a hex color, or a highlight group name
---@param sprite_color string|nil Color from sprite data (may be 'fallback')
---@param fallback_hlgroup string Default highlight group to use if sprite_color is 'fallback'
---@param brighten_params table|nil Optional brighten parameters: {lightness_amount, saturation_amount}
---@param dim_amount number|nil Optional dim amount (0-1) to blend with background
---@param bg_color string|nil Background color for dimming (defaults to Normal bg)
---@return string|nil color Resolved and adjusted hex color, or nil if resolution failed
local function resolve_color(value, sprite_color, fallback_hlgroup, brighten_params, dim_amount, bg_color)
  -- If user specified a direct override (not 'auto'), use it
  if value ~= "auto" then
    -- Check if it's a hex color
    if value:match("^#%x%x%x%x%x%x$") then
      value = value -- Already a hex color
    else
      -- Otherwise, treat it as a highlight group name
      local hl = vim.api.nvim_get_hl(0, { name = value, link = false })
      if hl and hl.fg then
        value = string.format("#%06x", hl.fg)
      else
        vim.notify(
          string.format("Could not resolve highlight group '%s', using fallback", value),
          vim.log.levels.WARN
        )
        value = nil -- Fall through to use sprite_color or fallback
      end
    end
  else
    -- User specified 'auto', so use sprite data
    if sprite_color and sprite_color ~= "fallback" then
      value = sprite_color
    else
      -- Sprite data says 'fallback' or is nil, use the fallback highlight group
      local hl = vim.api.nvim_get_hl(0, { name = fallback_hlgroup, link = false })
      if hl and hl.fg then
        value = string.format("#%06x", hl.fg)
      else
        vim.notify(
          string.format("Could not resolve color from highlight group '%s'", fallback_hlgroup),
          vim.log.levels.WARN
        )
        return nil
      end
    end
  end

  -- At this point, value should be a hex color or nil
  if not value then
    return nil
  end

  -- Apply color adjustments if specified
  local color = value

  -- Apply brighten adjustment (increases lightness + saturation in HSLuv space)
  if brighten_params and type(brighten_params) == "table" then
    local ok, util = pcall(require, "tokyonight.util")
    if ok then
      local lightness = brighten_params[1]
      local saturation = brighten_params[2]
      color = util.brighten(color, lightness, saturation)
    else
      vim.notify("tokyonight.util not available for brighten adjustment", vim.log.levels.WARN)
    end
  end

  -- Apply dim adjustment (blend with background)
  if dim_amount and dim_amount > 0 then
    local ok, util = pcall(require, "tokyonight.util")
    if ok then
      -- Get background color if not provided
      if not bg_color then
        local normal_hl = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
        if normal_hl and normal_hl.bg then
          bg_color = string.format("#%06x", normal_hl.bg)
        else
          bg_color = "#000000" -- Fallback to black if no background found
        end
      end
      color = util.blend_bg(color, dim_amount, bg_color)
    else
      vim.notify("tokyonight.util not available for dim adjustment", vim.log.levels.WARN)
    end
  end

  return color
end

---Apply pokemon colors to Snacks dashboard highlight groups
---@param pokemon_data table Pokemon color data from database
---@param background_mode string|nil Optional background mode override: "auto", "light", "dark" (default: "auto")
---@param color_sources table|nil Optional config: {title_source, key_source, desc_source, *_brighten, *_dim}
function M.apply_dashboard_colors(pokemon_data, background_mode, color_sources)
  if not pokemon_data then
    return
  end

  -- Get colors from pokemon data for the current background
  local colors = M.get_colors_for_background(pokemon_data, background_mode)
  if not colors then
    return
  end

  -- Default color sources to 'auto' if not provided
  local sources = color_sources or {}
  local title_source = sources.title_source or "auto"
  local key_source = sources.key_source or "auto"
  local desc_source = sources.desc_source or "auto"

  -- Extract adjustment parameters
  local title_brighten = sources.title_brighten
  local key_brighten = sources.key_brighten
  local desc_brighten = sources.desc_brighten
  local title_dim = sources.title_dim
  local key_dim = sources.key_dim
  local desc_dim = sources.desc_dim

  -- Get background color once for dimming operations
  local bg_color
  local normal_hl = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
  if normal_hl and normal_hl.bg then
    bg_color = string.format("#%06x", normal_hl.bg)
  else
    bg_color = "#000000" -- Fallback to black
  end

  -- Resolve each color with appropriate fallbacks and adjustments
  -- Note: prominent/title should NEVER have 'fallback' in sprite data, but we handle it defensively
  local title_color = resolve_color(title_source, colors.prominent, "Normal", title_brighten, title_dim, bg_color)
  local key_color = resolve_color(key_source, colors.bright, "Normal", key_brighten, key_dim, bg_color)
  local desc_color = resolve_color(desc_source, colors.dim, "Comment", desc_brighten, desc_dim, bg_color)

  -- Update Snacks dashboard highlight groups
  -- SnacksDashboardTitle: prominent (used for main titles/headers)
  -- SnacksDashboardKey: bright (used for key hints/important text)
  -- SnacksDashboardDesc: dim (used for descriptions/secondary text)
  -- SnacksDashboardIcon: icons (mapped to key color for visual consistency)

  if title_color then
    vim.api.nvim_set_hl(0, "SnacksDashboardTitle", { fg = title_color })
  end
  if key_color then
    vim.api.nvim_set_hl(0, "SnacksDashboardKey", { fg = key_color })
    -- Map dashboard icons to key color for consistency
    vim.api.nvim_set_hl(0, "SnacksDashboardIcon", { fg = key_color })
  end
  if desc_color then
    vim.api.nvim_set_hl(0, "SnacksDashboardDesc", { fg = desc_color })
  end
end

---Ensure pokemon colors exist, generating them if necessary (ASYNC)
---This function will:
---1. Try to load colors for the pokemon
---2. If not found, start async generation and return nil immediately
---3. When generation completes, reload colors and update dashboard
---@param pokemon_name string The name of the pokemon
---@param is_shiny boolean|nil Whether this is a shiny variant
---@param form string|nil Optional form name
---@param on_complete function|nil Callback to run after generation completes
---@param background_mode string|nil Optional background mode override: "auto", "light", "dark" (default: "auto")
---@return table|nil colors Table with dark/light color variants, or nil if not found/generating
function M.ensure_pokemon_colors(pokemon_name, is_shiny, form, on_complete, background_mode)
  -- First, try to load the colors normally (without fallback to ensure exact match)
  local colors = M.get_pokemon_colors(pokemon_name, is_shiny, form, false)
  if colors then
    return colors
  end

  -- Colors not found - start async generation
  local display_name = pokemon_name .. (is_shiny and " (shiny)" or "")
  vim.notify(string.format("Generating color data for %s...", display_name), vim.log.levels.INFO)

  -- Find the script path (now located in the visual directory)
  local config_dir = vim.fn.stdpath("config")
  local script_path = config_dir .. "/lua/custom/visual/generate-pokemon-colors.sh"

  -- Check if script exists
  if vim.fn.filereadable(script_path) ~= 1 then
    vim.notify(string.format("Generation script not found at: %s", script_path), vim.log.levels.ERROR)
    return nil
  end

  -- Build command
  local cmd = { "zsh", script_path, pokemon_name, "--update-db" }
  if is_shiny then
    table.insert(cmd, "--shiny")
  end
  if form and form ~= "" then
    table.insert(cmd, "--form")
    table.insert(cmd, form)
  end

  -- Run the generation script asynchronously
  vim.fn.jobstart(cmd, {
    on_exit = function(_, exit_code, _)
      if exit_code ~= 0 then
        vim.notify(string.format("Failed to generate colors for %s", display_name), vim.log.levels.ERROR)
        return
      end

      -- Unload the module from the cache so we can reload it with the new entry
      package.loaded["custom.visual.pokemon-colors"] = nil

      -- Reload the module
      pokemon_colors = require("custom.visual.pokemon-colors")

      -- Try loading the newly generated colors
      local new_colors = M.get_pokemon_colors(pokemon_name, is_shiny, form, false)
      if new_colors then
        vim.notify(string.format("Successfully generated colors for %s", display_name), vim.log.levels.INFO)

        -- Apply the new colors with the provided background_mode
        M.apply_dashboard_colors(new_colors, background_mode)

        -- Call the completion callback if provided
        if on_complete then
          vim.schedule(on_complete)
        end
      else
        vim.notify(string.format("Generated colors but failed to load for %s", display_name), vim.log.levels.ERROR)
      end
    end,
  })

  -- Return nil immediately since generation is async
  return nil
end

return M
