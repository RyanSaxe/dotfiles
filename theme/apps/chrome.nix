# Chrome's theme, as the manifest of a theme extension: the tab strip in
# chrome, one surface with the bar and the window frames, and the toolbar
# and current tab on the background. Chrome loads it from
# ~/.config/theme/chrome, whose manifest.json links to this file.
{ lib, t, ... }:
let
  rgb =
    color:
    map (offset: lib.fromHexString (builtins.substring offset 2 color)) [
      1
      3
      5
    ];
in
{
  "chrome-manifest.json" = builtins.toJSON {
    manifest_version = 3;
    name = "Dotfiles";
    version = "1";
    theme.colors = lib.mapAttrs (_: rgb) {
      frame = t.chrome;
      frame_inactive = t.chrome;
      toolbar = t.background;
      tab_text = t.text;
      tab_background_text = t.muted;
      toolbar_text = t.text;
      toolbar_button_icon = t.muted;
      bookmark_text = t.text;
      omnibox_background = t.panel;
      omnibox_text = t.text;
      ntp_background = t.background;
      ntp_text = t.text;
    };
  };
}
