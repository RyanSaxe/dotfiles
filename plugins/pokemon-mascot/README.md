# pokemon-mascot

A herdr plugin that keeps a small pokemon sprite in the bottom-right corner
of the terminal, matching the accent colors the `theme` command extracted
from the same pokemon.

## How it works

Every invocation is one-shot and stateless, per herdr's plugin contract:

1. Read the current pokemon from the theme state
   (`~/.local/state/dotfiles/accents.conf`).
2. Take a fresh session snapshot over the socket.
3. Anchor: the bottom-right-most pane of the focused tab — deterministic,
   independent of focus and of where any command ran.
4. Normalize the cached sprite (crop to content, pad square) and place it
   with `pane.graphics.set`, clearing every other pane first.

herdr triggers this on `layout.updated`, `tab.focused`, `workspace.focused`,
and `pane.closed`, so resizes and splits self-heal. The `theme` command also
invokes `herdr-pokemon place` after a pokemon switch.

Rapid event bursts (drag-resizing) coalesce: a lock skips concurrent runs
and a dirty marker makes the running instance re-place once more at the end.

## Requirements

- herdr with `[experimental] kitty_graphics = true` and a kitty
  graphics-capable outer terminal (ghostty)
- `uv` (the binary is a PEP 723 script)
- Sprites are cached by `pokemon-accents` (the theme system's extractor)

## Install

```sh
herdr plugin link /path/to/plugins/pokemon-mascot
```

`install.sh` does this automatically.

## Configuration

Size via environment for now: `MASCOT_COLS` (default 10), `MASCOT_ROWS`
(default 5).
