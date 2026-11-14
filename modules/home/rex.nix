# Rex installs and updates itself. This links its config from the
# checkout and writes the settings kept in its macOS preferences, which
# the switch owns: a change made in Rex's settings window lasts until the
# next switch.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles;
  personalMac = lib.elem "personal" cfg.roles && pkgs.stdenv.hostPlatform.isDarwin;
  domain = "com.superlogical.rex";
  # The terminal colors, from theme/apps/terminal.nix, as Rex keeps them.
  themes = lib.genAttrs [ "dark" "light" ] (
    mode: builtins.fromJSON config.xdg.configFile."theme/${mode}/rex-theme.json".text
  );
  customThemes = pkgs.writeText "rex-themes.json" (
    builtins.toJSON [
      themes.dark
      themes.light
    ]
  );
in
lib.mkMerge [
  # Rex's server reads its key bindings from this folder, so the Linux
  # computer that runs one gets it too.
  (lib.mkIf (personalMac || lib.elem "rex-server" cfg.roles) {
    xdg.configFile."rex".source = config.lib.file.mkOutOfStoreSymlink "${cfg.repo}/config/rex";
  })

  (lib.mkIf personalMac {
    # Rex adds the folder holding its rex command to a terminal's PATH, but
    # nix-darwin's /etc/zshenv sets PATH from scratch in every new shell.
    home.sessionPath = [
      "${config.home.homeDirectory}/Library/Application Support/com.superlogical.rex/RexServer/Versions/Current/Rex Server.app/Contents/MacOS"
    ];

    # `defaults import` merges these keys and leaves Rex's other state alone.
    targets.darwin.defaults.${domain} = {
      # Layout
      "Workspace.tabStyle" = "vertical";
      "Workspace.sidebarPosition" = "left";
      "Workspace.sidebarCollapsed" = false;
      "Workspace.sidebarShowsActivity" = false;
      "Workspace.sidebarTextPointSize" = 13.0;
      "Workspace.tabIconCount" = 3;
      "Workspace.tabIconTintMode" = "off";
      "Workspace.paneDensity" = "comfortable";
      "Workspace.inactivePaneFadeMode" = "both";
      "Workspace.usesStandardInactiveWindowPaneStyles" = true;
      "Workspace.usesPaneGlass" = false;
      "Workspace.interfaceStyle" = "useTheme";
      "Workspace.appearance" = "system";

      # Font
      "Workspace.terminalFontName" = "FiraCode Nerd Font Mono";
      "Workspace.terminalFontPointSize" = 12.0;
      "Workspace.terminalFontStyle" = "Retina";
      "Workspace.terminalFontSmoothing" = true;
      "Workspace.terminalCellHeightPercent" = 0.0;
      "Workspace.terminalCharacterSpacing" = "0";

      # Server
      "rex.server.tailnet-enabled" = true;
      "rex.client.remoteControl" = true;
      "rex.agents.names-sessions" = false;
      "rex.server.automatic-restart-enabled" = true;
      SUAutomaticallyUpdate = true;
      SUEnableAutomaticChecks = true;

      # Developer extras
      "rex.developer-mode-enabled" = true;
      "Workspace.cursorShadersEnabled" = true;
      "Workspace.cursorShader" = "blazeTapered";
      "Workspace.experiments.usesNewQuickSwitcher" = true;

      # The two themes below, by their ids.
      "Workspace.darkThemeID" = themes.dark.id;
      "Workspace.lightThemeID" = themes.light.id;
    };

    # Rex keeps its themes as one JSON document stored as plist data, which
    # the defaults module can't write, so this writes both themes as that list.
    home.activation.rexThemes = lib.hm.dag.entryAfter [ "setDarwinDefaults" ] ''
      run /usr/bin/defaults write ${domain} Workspace.customThemes -data \
        "$(/usr/bin/xxd -p ${customThemes} | tr -d '\n')"
    '';
  })
]
