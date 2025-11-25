# Karabiner-Elements Configuration

Advanced keyboard remapping system that transforms Right Shift into a dual-purpose key (F18 tap / Hyper hold) and enables vim-style navigation globally across macOS.

## Features

- **Right Shift dual-purpose** - Tap for F18 (Leader Key trigger), hold for Hyper key
- **Hyper key** - `Cmd+Ctrl+Opt+Shift` held by Right Shift
- **Vim navigation** - `Hyper + HJKL` for arrow keys system-wide
- **Hyper + other keys** - Additional ergonomic shortcuts for common actions

## Key Concept: Hyper Key

The "Hyper" key is a modifier combination (`Cmd+Ctrl+Opt+Shift`) that's rarely used by default applications, making it perfect for custom global shortcuts without conflicts.

### Why Right Shift?

- Ergonomic position for thumb/pinky
- Rarely used key (most people only use Left Shift)
- Easy to reach without moving hand position
- No conflicts with existing shortcuts

## Primary Mappings

### Right Shift Behavior

```text
Tap (< 200ms)    → F18 (triggers Leader Key)
Hold (≥ 200ms)   → Hyper (Cmd+Ctrl+Opt+Shift)
```

### Hyper + HJKL (Vim Navigation)

```text
Hyper + H  → Left Arrow
Hyper + J  → Down Arrow
Hyper + K  → Up Arrow
Hyper + L  → Right Arrow
```

This enables vim-style navigation in:

- Web browsers (scrolling, form fields)
- Text editors (native macOS text fields)
- System dialogs
- Any application that accepts arrow keys

### Additional Hyper Keybindings

See the `complex_modifications.rules` array in `karabiner.json` for the complete list of Hyper key combinations. Common patterns include:

- **Navigation** - Browser controls, tab switching
- **Window management** - Move/resize windows (if combined with window managers)
- **Application shortcuts** - Quick access to frequently used apps

## Configuration Structure

```text
karabiner/
├── karabiner.json              # Main configuration
└── automatic_backups/          # Auto-generated backups
    └── karabiner_*.json
```

The `karabiner.json` file contains:

- `global` - General Karabiner settings
- `profiles` - Named keyboard mapping profiles (e.g., "Ryan's Profile")
- `complex_modifications.rules` - Advanced key remapping logic

## How Complex Modifications Work

Each rule has:

```json
{
  "description": "Human-readable description",
  "manipulators": [
    {
      "type": "basic",
      "from": { /* source key(s) */ },
      "to_if_alone": [ /* tap action */ ],
      "to_if_held_down": [ /* hold action */ ],
      "to": [ /* normal press action */ ],
      "parameters": { /* timing thresholds */ }
    }
  ]
}
```

### Key Parameters

- **`to_if_alone_timeout_milliseconds`** - Max time for "tap" (default: 200ms)
- **`to_if_held_down_threshold_milliseconds`** - Min time for "hold" (default: 200ms)

## Integration with Leader Key

The F18 tap action is what triggers Leader Key (configured to listen for F18 in Leader Key app settings). This creates a "leader key pattern" similar to Vim/Tmux:

1. Tap Right Shift → F18 → Leader Key menu appears
2. Type key sequence → Execute action
3. Result: Fast, discoverable shortcuts without memorizing complex modifier combinations

## Customization

Edit `karabiner.json` to:

- Add new Hyper key combinations
- Change timing thresholds for tap/hold detection
- Add additional complex modifications
- Create multiple profiles for different use cases
- Remap other keys (Caps Lock, function keys, etc.)

**Note:** Karabiner-Elements GUI (`Karabiner-Elements Preferences`) can also be used to:

- Enable/disable rules
- Import/export configurations
- Test modifications
- View event logs for debugging

See [Karabiner-Elements docs](https://karabiner-elements.pqrs.org/docs/) for complete reference.

## Troubleshooting

- **Karabiner not working** - Check System Settings → Privacy & Security → Input Monitoring (Karabiner needs permission)
- **Wrong timing** - Adjust `parameters` milliseconds in the rule
- **Conflicts** - Check for overlapping system shortcuts in System Settings → Keyboard → Keyboard Shortcuts
