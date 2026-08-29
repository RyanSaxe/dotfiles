# Theming

Catppuccin — Mocha in dark, Latte in light — rendered from one token file into
every tool. No config hardcodes a color; apps consume generated palettes and
reload in place.

```sh
theme dark
theme light
theme inner light
theme outer dark
theme both toggle
theme mascot pokemon:gengar   # accent colors extracted from a mascot image
theme mascot local:cat.png      # a machine-local image
```

## Two surfaces

The theme has two independently switchable layers:

| Layer   | What it covers                                                                                            |
| ------- | --------------------------------------------------------------------------------------------------------- |
| `inner` | terminal and content chrome — ghostty's native palette, shells, prompts, bat, the editor's buffers        |
| `outer` | the surrounding chrome — sketchybar, the rail, tmux separators, the ghostty frame shader, editor sidebars |

Inner mode drives macOS appearance so ghostty keeps its native light/dark theme
pair; outer mode never changes the OS appearance. This permits combinations such
as a light terminal inside dark chrome.

The split is not decorative. It answers one question per surface: **does this
touch a terminal edge?** A float hovering over a buffer is inner; a sidebar
running to the edge continues the tmux rail and is outer.

## The pipeline

```text
palettes/*.conf     raw catppuccin values, verbatim
   -> tokens.conf   roles: bg, fg_muted, border, warn, ...
   -> elements.conf which context each rendered file uses
   -> templates/    one per consumer
   -> ~/.local/state/dotfiles/generated/
```

Every consumer is registered as inner, outer, or mixed in
`theme/elements.conf`. Mixed consumers get both namespaces and
must qualify every placeholder — `{{inner_bg}}`, `{{outer_crust}}` — because a
bare name would silently pick one layer.

The native palette keys preserve their upstream Catppuccin values: the theme's
identity lives in the **role assignments**, not in custom hex values. The
palettes also contain dotfiles-owned keys used by generated consumers:
`semantic_*` keys for diff rendering and `os_window_stroke` for the macOS
window border. Both palettes must define the same key set so every consumer
can render in either mode; CI checks that invariant.

### Neovim

`nvim-tokens.lua` renders in the mixed context, because the editor spans both
layers: its buffers are inner, but the tab row's fill and any sidebar touch an
edge. `lua/theme/highlights.lua` is the semantic layer and the file to extend —
add groups referencing the role tables, never a raw hex.

Windows opt into the outer surface through `lua/theme/surfaces.lua`, which keys
on whether a window is anchored rather than on plugin names, so a new sidebar
plugin is themed the day it is installed.

### Bat and delta

`Dotfiles.tmTheme` renders in the inner context and is published to bat's theme
directory. Git delta selects that generated theme explicitly. Bat and delta do
not receive Neovim's semantic tokens, so the compact TextMate scope map mirrors
the same function, type, structure, variable, member, module, constant, and
literal roles as closely as their syntax grammars allow.

## Using color

Two rules decide which token a thing gets. Both exist so that changing the
mascot can never make text unreadable or a state ambiguous.

**Mascot-derived tokens accentuate structure, not text.** `accent` and
`notify` are extracted from whatever mascot is worn, so their hue and contrast
change without warning. Spend them on shape — the highlighted tab, a divider,
a selection marker, a focused border — where a shifted hue reads as a
different mood rather than a legibility problem. Never color running text,
table cells, or a search match with them: the gold of one mascot sits almost
invisibly on a red row that the cyan of another mascot would have carried.

**Text takes native palette colors.** Anything a reader parses as language
uses the palette keys directly — `red`, `peach`, `mauve`, `green`, `yellow`,
`lavender` — because those are fixed by the Catppuccin flavour and stay
legible in both modes. Semantic roles keep their meanings (`tokens.conf` is
the source of truth); the remaining native colors are free for
non-semantic text emphasis such as a search match, which is what `yellow`
is used for in the rail's dashboards.

The practical test: if the mascot changed to something with the opposite
brightness, would this element become hard to read or hard to interpret? If
yes, it wants a native color.

## Mascot providers

A mascot is any image the theme system can wear: the rail paints its sprite and
the accent/notify colors are extracted from it. Identities are
provider-qualified (`pokemon:gengar`), and providers live in
`theme/bin/mascot-accents.py` as a registry — the picker, completions,
and rail all build from it, so adding a source touches exactly one file.

A provider is two functions registered under a name:

```python
def _my_identities() -> list[str]:
    # What the picker offers. An API list, a directory of dropped
    # images (identity = filename), anything enumerable.
    ...


def _my_fetch(identity: str) -> MascotImages:
    # Cache under mascot_cache("my-source") and return the sprite PNG
    # the rail paints plus the image accents extract from — often the
    # same file (pokemon extracts from richer official artwork).
    ...


register("my-source", Provider(_my_identities, _my_fetch))
```

That's the whole surface. `theme mascot my-source:<id>`, the fzf picker entry,
per-project sync, and the rail sprite all follow from the registration — see the
`pokemon` provider for a full example and `shiny-pokemon` for wrapping an
existing source as its own picker entry.

### Local images

Put PNG files in `$XDG_DATA_HOME/dotfiles/mascots`. When `XDG_DATA_HOME` is
unset, use `~/.local/share/dotfiles/mascots`. The local provider lists the PNG
filenames in that directory as relative identities, such as `local:cat.png`,
and resolves the selected file at runtime.
