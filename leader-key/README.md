# Leader Key Configuration

Leader Key is a macOS application launcher that uses a "leader key" pattern
(similar to Vim/Tmux) to trigger actions.

## Setup

### 1. Installation

Leader Key is installed via Homebrew (already in `config/brew-packages.txt`):

```bash
brew install --cask leader-key
```

### 2. Symlink Configuration

The symlink is already configured in `config/symlinks.txt`:

```
leader-key/config.json:$HOME/Library/Application Support/Leader Key/config.json
```

Run the symlink script to create the link:

```bash
./scripts/symlink.sh
```

### 3. Set Command+Space as Leader Key (Manual Step)

**Important:** The leader key shortcut is set in the Leader Key app GUI, NOT in
config.json.

#### Free Command+Space from Spotlight:

1. Open **System Settings** → **Keyboard** → **Keyboard Shortcuts**
2. Click **Spotlight** in the sidebar
3. Uncheck "Show Spotlight search" or change it to another shortcut (e.g.,
   Cmd+Shift+Space)

#### Set Leader Key to Command+Space:

1. Open **Leader Key** app (from Applications or menu bar icon)
2. Click the menu bar icon → **Settings** (or press ⌘+,)
3. In the **Shortcut** field, press **Command+Space**
4. The app should now show "⌘Space" as your leader key

## Features

### Cheatsheet Display

- **Built-in feature** - When you press the leader key (⌘Space), Leader Key
  automatically displays a cheatsheet showing all available actions
- No configuration needed

### Breadcrumbs Navigation

- **Built-in feature** - When navigating nested groups, Leader Key shows a
  breadcrumb trail
- For example: Press ⌘Space, then `w` (Windows) - you'll see "Windows" in the
  breadcrumb as you choose sub-actions

### Spotlight via Double-Space

- After pressing the leader key (⌘Space), press `space` to open Spotlight
- This gives you: ⌘Space → Space → Spotlight opens
- Configured in the first action of `config.json`

## Configuration Structure

The `config.json` file uses this structure:

```json
{
  "type": "group",
  "actions": [
    {
      "key": "t",
      "label": "Terminal",
      "type": "application",
      "value": "/Applications/Ghostty.app"
    },
    {
      "key": "g",
      "label": "Git",
      "type": "group",
      "actions": [
        // Nested actions...
      ]
    }
  ]
}
```

### Action Types

1. **application** - Opens a macOS application

   ```json
   {
     "key": "t",
     "label": "Terminal",
     "type": "application",
     "value": "/Applications/Ghostty.app"
   }
   ```

2. **command** - Runs a shell command

   ```json
   {
     "key": "s",
     "label": "Git Status",
     "type": "command",
     "value": "git status"
   }
   ```

3. **url** - Opens a URL (including custom schemes like `raycast://`)

   ```json
   {
     "key": "e",
     "label": "Emoji",
     "type": "url",
     "value": "raycast://extensions/raycast/emoji-symbols/search-emoji-symbols"
   }
   ```

4. **group** - Creates a nested menu (breadcrumbs navigation)
   ```json
   {
     "key": "g",
     "label": "Git",
     "type": "group",
     "actions": [
       /* nested actions */
     ]
   }
   ```

## Integration with Hammerspoon

The config includes examples of triggering Hammerspoon functions via the `hs`
command-line tool:

```json
{
  "key": "r",
  "label": "Reload Hammerspoon",
  "type": "command",
  "value": "hs -c 'hs.reload()'"
}
```

This allows you to use Leader Key as a simple launcher and delegate complex
logic to Hammerspoon scripts.

## Customization

Edit `~/generic/dotfiles/leader-key/config.json` to add your own shortcuts.
Changes are immediately reflected in the Leader Key app (it auto-reloads on
config changes).

### Tips:

- Keep `key` values as single characters
- Use descriptive `label` values for the cheatsheet
- Group related actions under a common prefix (e.g., all git commands under `g`)
- Use `type: "group"` for nested menus to keep the top level clean

## TODO

### Simple

- [ ] Create fully exhaustive keybind list to make navigation extremely easy and
      discoverable
