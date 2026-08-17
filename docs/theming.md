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
`theme/dot-config/theme/elements.conf`. Mixed consumers get both namespaces and
must qualify every placeholder — `{{inner_bg}}`, `{{outer_crust}}` — because a
bare name would silently pick one layer.

The palette files stay upstream-pure: the theme's identity lives in the **role
assignments**, not in custom hex values. The only additions are the three
`semantic_*` keys for diff rendering.

### Neovim

`nvim-tokens.lua` renders in the mixed context, because the editor spans both
layers: its buffers are inner, but the tab row's fill and any sidebar touch an
edge. `lua/theme/highlights.lua` is the semantic layer and the file to extend —
add groups referencing the role tables, never a raw hex.

Windows opt into the outer surface through `lua/theme/surfaces.lua`, which keys
on whether a window is anchored rather than on plugin names, so a new sidebar
plugin is themed the day it is installed.

## Mascot providers

A mascot is any image the theme system can wear: the rail paints its sprite and
the accent/notify colors are extracted from it. Identities are
provider-qualified (`pokemon:gengar`), and providers live in
`theme/dot-local/bin/mascot-accents` as a registry — the picker, completions,
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
