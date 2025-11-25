# Hammerspoon Configuration

Hammerspoon automation for macOS, currently focused on Chrome tab management and
integration with Leader Key.

## Features

- **Chrome tab focusing** - Focus existing Chrome tabs by domain, or open new
  ones if not found
- **IPC enabled** - Command-line tool (`hs`) can communicate with Hammerspoon
- **Leader Key integration** - Trigger Hammerspoon functions via Leader Key
  shortcuts

## Current Implementation

### Tab Focusing Automation

The main functionality provides intelligent Chrome tab management:

1. **Search all Chrome windows** - Enumerates all tabs across all Chrome windows
2. **Match by domain** - Finds tabs matching a given domain pattern
3. **Focus or open** - If a matching tab exists, focuses it; otherwise opens a
   new tab
4. **Robust window handling** - Uses window IDs (stable across
   reordering/minimization)

### How It Works

```lua
-- Example: Focus or open GitHub
focusOrOpenTab("github.com")
```

This function:

- Searches all Chrome tabs for URLs containing "github.com"
- If found, brings Chrome to front and activates that tab (even if minimized)
- If not found, opens a new tab with the URL

### Integration with Leader Key

Hammerspoon functions can be called from Leader Key via the `hs` command-line
tool:

```json
{
  "key": "r",
  "label": "Reload Hammerspoon",
  "type": "command",
  "value": "hs -c 'hs.reload()'"
}
```

This pattern allows Leader Key to serve as a simple launcher while delegating
complex automation logic to Hammerspoon scripts.

## Current Limitations

- **Chrome-only** - Currently only supports Google Chrome for guaranteed
  performance
- **Future expansion** - Could support other Chromium browsers (Arc, Brave,
  Edge) by detecting default browser and swapping app name in AppleScript
- **Firefox/Safari** - Have different/limited AppleScript APIs and would require
  separate implementations

## Customization

Edit `init.lua` to:

- Add new automation functions
- Support additional browsers
- Create window management shortcuts
- Add keyboard remapping or hotkeys
- Integrate with other macOS applications

See [Hammerspoon docs](https://www.hammerspoon.org/docs/) for the full API
reference.

## TODO

### Unclear How Hard

- [ ] Refactor init.lua into a proper Spoon
- [ ] Create additional Spoons with automation that integrates cleanly with
      Leader Key
- [ ] Expand browser support beyond Chrome
