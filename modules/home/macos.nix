# The macOS settings that belong to the user: Ctrl-Space freed for Rex and
# tmux, and Caps Lock per keyboard.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  # HID usage codes: Caps Lock, Escape, left and right Control.
  caps = 30064771129;
  escape = 30064771113;
  leftControl = 30064771296;
  rightControl = 30064771300;
  map' = src: dst: {
    HIDKeyboardModifierMappingSrc = src;
    HIDKeyboardModifierMappingDst = dst;
  };
  capsToEscape = [ (map' caps escape) ];

  # Ctrl-Space and Ctrl-Alt-Space stop switching input sources.
  hotkey = id: mods: ''
    run /usr/bin/defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add ${id} \
      '<dict><key>enabled</key><false/><key>value</key><dict><key>parameters</key><array><integer>32</integer><integer>49</integer><integer>${mods}</integer></array><key>type</key><string>standard</string></dict></dict>'
  '';
in
lib.mkIf (lib.elem "gui" config.dotfiles.roles && pkgs.stdenv.hostPlatform.isDarwin) {
  # Keyed by vendor-product: the built-in keyboard, two Logitech
  # keyboards, and one with Caps Lock and Control swapped. They apply at
  # the next login.
  targets.darwin.currentHostDefaults.NSGlobalDomain = {
    "com.apple.keyboard.modifiermapping.0-0-0" = capsToEscape;
    "com.apple.keyboard.modifiermapping.6645-12869-0" = capsToEscape;
    "com.apple.keyboard.modifiermapping.6645-12871-0" = capsToEscape;
    "com.apple.keyboard.modifiermapping.9610-22-0" = [
      (map' leftControl caps)
      (map' rightControl caps)
      (map' caps rightControl)
    ];
  };

  home.activation.macos = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    ${hotkey "60" "262144"}
    ${hotkey "61" "786432"}
    run /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u || true
  '';
}
