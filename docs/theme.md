# Theme

```sh
theme light   # switch macOS and every app to Catppuccin Latte
theme dark    # switch them to Catppuccin Mocha
theme         # follow macOS's appearance
```

Changing the appearance in macOS works too, because sketchybar runs `theme`
whenever it changes.

<img alt="The Mac's screen in dark mode, in Catppuccin Mocha: sketchybar across the top, and Rex below it with two Neovim panes." src="../assets/screen.png">

## How it works

`theme/meanings.nix` names what each color means, such as `muted` or
`code.function`, once for each mode. Each file in `theme/apps` turns those
meanings into one app's files. Each home switch renders every app for both
modes, into `~/.config/theme/dark` and `~/.config/theme/light`, and
`theme` points the links in `~/.config/theme` at one mode. tmux, Ghostty,
sketchybar and Claude Code keep their colors in memory, so `theme` reloads
them too. A computer without Claude Code gets none of Claude Code's theme
files.

A Mac with a screen also gets a desktop picture for each mode, painted
from the theme's colors by `theme/desktop.py`, and `theme` sets it on
every screen at each switch. A computer whose desktop picture is managed
elsewhere sets `dotfiles.desktopPicture = false` in its host file, and
`theme` then leaves the picture alone.

## Color another app

Add a file to `theme/apps` that takes the meanings as `t` and returns each
file the app reads, by name:

```nix
# theme/apps/statusline.nix
{ t, ... }:
{
  "ai-statusline-colors.js" = "module.exports = ${
    builtins.toJSON {
      faint = t.faint;
      project = t.repo.project;
      model = t.info;
    }
  };\n";
}
```

Point the app at its file in `~/.config/theme`, here
`~/.config/theme/ai-statusline-colors.js`. Use only meanings, never a hex.
An app that keeps its colors in memory also needs a reload line in
`theme/theme.sh`.

## Chrome

Chrome's theme is an extension in `~/.config/theme/chrome`, which each
computer loads once, as [By hand](manual.md#chrome-on-a-mac) says. Its
frame and tabs are the chrome color, like sketchybar, and its toolbar and
selected tab the raised color of Neovim's current line. Chrome builds a
theme only when it starts, so when the mode changes `theme` quits Chrome
and opens it again.
