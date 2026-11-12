# The macOS settings each switch writes. Anything not set here stays
# however it was set by hand.
{ config, lib, ... }:
let
  inherit (config.dotfiles) user;
in
lib.mkIf (lib.elem "gui" config.dotfiles.roles) {
  system.defaults = {
    NSGlobalDomain = {
      _HIHideMenuBar = true;
      "com.apple.swipescrolldirection" = false;
    };
    ".GlobalPreferences"."com.apple.mouse.scaling" = 3.0;

    dock = {
      autohide = true;
      tilesize = 30;
      persistent-apps = map (app: { app = "/System/Applications/${app}.app"; }) [
        "Apps"
        "Messages"
        "FaceTime"
        "Calendar"
        "Contacts"
        "Reminders"
        "Notes"
        "App Store"
        "System Settings"
        "iPhone Mirroring"
      ];
      persistent-others = [
        {
          folder = {
            path = "/Users/${user}/Downloads";
            arrangement = "date-added";
            displayas = "stack";
            showas = "fan";
          };
        }
      ];
    };

    finder.FXPreferredViewStyle = "Nlsv";
    screencapture.location = "~/Desktop/ScreenShots";

    WindowManager = {
      EnableStandardClickToShowDesktop = false;
      StandardHideDesktopIcons = true;
      HideDesktop = true;
    };

    SoftwareUpdate.AutomaticallyInstallMacOSUpdates = true;
    CustomSystemPreferences."com.apple.commerce".AutoUpdate = false;
    CustomUserPreferences = lib.mkIf (lib.elem "personal" config.dotfiles.roles) {
      "io.tailscale.ipn.macsys".TailscaleStartOnLogin = true;
    };
  };

  system.activationScripts.postActivation.text = ''
    sudo -u ${user} mkdir -p /Users/${user}/Desktop/ScreenShots
  '';
}
