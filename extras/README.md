# Extras

Small configuration files and themes for various tools that don't warrant their own top-level directory.

## Contents

### fsh/ - fast-syntax-highlighting

Custom themes for [zdharma-continuum/fast-syntax-highlighting](https://github.com/zdharma-continuum/fast-syntax-highlighting).

- `tokyonight.ini` - TokyoNight Night theme matching the Neovim colorscheme

**Activation:**

```bash
# Apply the theme (run once, persists across sessions)
fast-theme ~/.config/fsh/tokyonight.ini
```

**Color mapping:**

| Element | Color | Hex |
| --------- | ------- | ----- |
| commands/builtins | orange | `#ff9e64` |
| keywords (if/for/while) | purple | `#9d7cd8` |
| strings | yellow | `#e0af68` |
| variables | blue | `#7aa2f7` |
| paths | cyan | `#7dcfff` |
| options/flags | green | `#9ece6a` |
| comments | gray | `#545c7e` |
| errors | red | `#f7768e` |
