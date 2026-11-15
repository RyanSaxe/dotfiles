# Claude Code and Codex. On a Mac both install and update themselves, so
# their modules have no package. Linux installs them from nixpkgs, and
# Claude Code only on a personal computer. Either way the modules only
# merge settings into each agent's own file, keeping whatever the agent
# writes there itself. Skills from other installers, such as byor, Rex and
# pair, stay with those tools.
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  cfg = config.dotfiles;
  link = path: config.lib.file.mkOutOfStoreSymlink "${cfg.repo}/${path}";
  pair = pkgs.callPackage ../../pkgs/pair { src = inputs.pair; };

  personal = lib.elem "personal" cfg.roles;
  inherit (pkgs.stdenv.hostPlatform) isLinux isDarwin;
  # Where the agents' commands are, which the switch's own PATH leaves out.
  agentPath =
    if isLinux then "${config.home.path}/bin" else "$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin";
  linkSkills = "${cfg.repo}/ai-harness/tools/link-agent-skills.sh";
  convertAgents = [
    "${pkgs.uv}/bin/uv"
    "run"
    "--quiet"
    "--python"
    "${pkgs.python3}/bin/python3"
    "--script"
    "${cfg.repo}/ai-harness/tools/convert-codex-agents.py"
  ];

  skills = {
    worktrees = link "ai-harness/skills/worktrees";
    wiki = link "ai-harness/skills/wiki";
  };
  skillLinks =
    dir: lib.mapAttrs' (name: source: lib.nameValuePair "${dir}/${name}" { inherit source; }) skills;

  # pi writes its own settings file, so the switch sets only the theme key:
  # the theme for each background, light first, which pi switches between
  # as the terminal's background changes.
  piTheme = pkgs.writeShellScript "pi-theme" ''
    settings="$HOME/.pi/agent/settings.json"
    mkdir -p "''${settings%/*}"
    [ -s "$settings" ] || echo '{}' > "$settings"
    ${pkgs.jq}/bin/jq '.theme = "dotfiles-light/dotfiles-dark"' "$settings" > "$settings.new"
    mv "$settings.new" "$settings"
  '';

  # pair's hub wakes pi through an extension and opencode through a plugin.
  # Each is registered from the profile, whose path stays the same when
  # pair updates, in place of the store path `pair start` prints.
  pairAdapters = "${config.home.profileDirectory}/lib/pair/adapters";
  opencodePlugin =
    if lib.versionAtLeast pkgs.opencode.version "2" then "opencode" else "opencode/plugin.js";
  pairPlugins = pkgs.writeShellScript "pair-plugins" ''
    set -eu
    jq=${pkgs.jq}/bin/jq
    register() { # FILE KEY PATH: list PATH under KEY, dropping older copies
      "$jq" --arg key "$2" --arg path "$3" --arg tail "''${3#${config.home.profileDirectory}}" \
        '.[$key] = [(.[$key] // [])[] | select(type != "string" or (endswith($tail) | not))] + [$path]' \
        "$1" > "$1.new"
      mv "$1.new" "$1"
    }

    pi="$HOME/.pi/agent/settings.json"
    mkdir -p "''${pi%/*}"
    [ -s "$pi" ] || echo '{}' > "$pi"
    register "$pi" packages "${pairAdapters}/pi/extension.js"

    # opencode reads the first of opencode.jsonc, opencode.json and
    # config.json that exists, which is the last one this loop finds.
    dir="${config.xdg.configHome}/opencode"
    mkdir -p "$dir"
    opencode="$dir/opencode.json"
    for name in config.json opencode.json opencode.jsonc; do
      if [ -e "$dir/$name" ]; then opencode="$dir/$name"; fi
    done
    [ -s "$opencode" ] || echo '{}' > "$opencode"
    # opencode 2 loads pair's plugin folder, and opencode 1 the plugin.js in
    # it. List the one the installed opencode loads, and drop the other.
    "$jq" '.plugin = [(.plugin // [])[] | select(type != "string" or ((endswith("/lib/pair/adapters/opencode") or endswith("/lib/pair/adapters/opencode/plugin.js")) | not))]' \
      "$opencode" > "$opencode.new"
    mv "$opencode.new" "$opencode"
    register "$opencode" plugin "${pairAdapters}/${opencodePlugin}"
  '';

  # `pair agents` lists a session once it registers, so other agents can
  # message it. Claude Code registers each session from a SessionStart hook.
  # Rex writes its own hook in that list, so this adds pair's beside it.
  pairRegister = "${config.home.profileDirectory}/bin/pair register --hook";
  pairStartHook = pkgs.writeShellScript "pair-start-hook" ''
    set -eu
    jq=${pkgs.jq}/bin/jq
    settings="$HOME/.claude/settings.json"
    [ -s "$settings" ] || exit 0
    if ! "$jq" -e --arg command '${pairRegister}' \
      '[.hooks.SessionStart[]?.hooks[]?.command] | index($command)' "$settings" > /dev/null; then
      "$jq" --arg command '${pairRegister}' \
        '.hooks.SessionStart = (.hooks.SessionStart // []) + [{hooks: [{type: "command", command: $command}]}]' \
        "$settings" > "$settings.new"
      mv "$settings.new" "$settings"
    fi
  '';

  pushover = name: "${cfg.repo}/ai-harness/tools/notify-pushover.zsh '${name}'";
  claudeHook =
    matcher:
    lib.optionalAttrs (matcher != null) { inherit matcher; }
    // {
      hooks = [
        {
          type = "command";
          command = pushover "Claude Code";
        }
      ];
    };
in
lib.mkIf (lib.elem "base" cfg.roles) {
  home.packages = [ pair ];

  home.file = {
    # Claude reads the instructions through an import. Codex can't import,
    # so it gets them through developer_instructions below.
    ".claude/CLAUDE.md".text = ''
      @${cfg.repo}/ai-harness/AGENTS.md
    '';
    ".claude/statusline.js".source = link "ai-harness/statusline.js";
    ".codex/themes/dotfiles.tmTheme".source =
      config.lib.file.mkOutOfStoreSymlink "${config.xdg.configHome}/theme/Dotfiles.tmTheme";
    ".claude/themes/dotfiles.json".source =
      config.lib.file.mkOutOfStoreSymlink "${config.xdg.configHome}/theme/claude-theme.json";
  }
  // lib.optionalAttrs personal {
    # Copilot CLI registers each session with pair from this start hook.
    ".copilot/hooks/pair.json".text = builtins.toJSON {
      version = 1;
      hooks.sessionStart = [
        {
          type = "command";
          bash = pairRegister;
          timeoutSec = 30;
        }
      ];
    };
  }
  // skillLinks ".claude/skills"
  // skillLinks ".agents/skills"
  // lib.optionalAttrs personal (
    lib.genAttrs' [ "dark" "light" ] (
      mode:
      lib.nameValuePair ".pi/agent/themes/dotfiles-${mode}.json" {
        source = config.lib.file.mkOutOfStoreSymlink "${config.xdg.configHome}/theme/${mode}/pi-theme.json";
      }
    )
  );

  xdg.configFile = lib.mkMerge [
    # Codex reads its managed hooks from /etc/codex, which Home Manager can't
    # write. A Linux computer links that folder to these files once:
    #   sudo ln -sfn ~/.config/codex/managed /etc/codex
    (lib.mkIf isLinux (
      lib.mapAttrs' (
        name: source:
        lib.nameValuePair "codex/managed/${name}" {
          source = if builtins.isPath source then source else config.lib.file.mkOutOfStoreSymlink source;
        }
      ) (import ../codex-managed.nix cfg.repo)
    ))
    # pair's Start agent and `pair spawn` run this script to open a new
    # agent in Rex, tmux or Terminal.
    (lib.mkIf (lib.elem "gui" cfg.roles && isDarwin) {
      "pair/spawn".source = link "config/pair/spawn";
    })
  ];

  programs.claude-code = {
    enable = true;
    package = if isLinux && personal then pkgs.claude-code else null;
    mutableSettings = true;
    settings = {
      model = "opus[1m]";
      effortLevel = "medium";
      # Compact at 80% of the 1M window, and never while a session sits idle.
      env.CLAUDE_AUTOCOMPACT_PCT_OVERRIDE = "80";
      idleCompaction = false;
      alwaysThinkingEnabled = true;
      editorMode = "vim";
      theme = "custom:dotfiles";
      statusLine = {
        type = "command";
        command = "$HOME/.claude/statusline.js";
        padding = 0;
      };
      permissions = {
        defaultMode = "auto";
        allow = [ "Bash(gh pr merge:*)" ];
      };
      # The merge replaces only these three lists, so byor's tool-use
      # hooks and Rex's session-start hook stay as those tools wrote them.
      hooks = {
        Stop = [ (claudeHook null) ];
        Notification = [ (claudeHook "permission_prompt|elicitation_dialog|agent_needs_input") ];
        StopFailure = [ (claudeHook null) ];
      };
    };
  };

  programs.codex = {
    enable = true;
    package = if isLinux then pkgs.codex else null;
    mutableSettings = true;
    settings = {
      model = "gpt-6.1-sol";
      model_reasoning_effort = "medium";
      # gpt-6.1-sol's largest window, compacted at 80% of it.
      model_context_window = 872000;
      model_auto_compact_token_limit = 697600;
      # An edit to the repo's file reaches Codex at the next home switch.
      developer_instructions = builtins.readFile ../../ai-harness/AGENTS.md;
      service_tier = "default";
      approval_policy = "on-request";
      approvals_reviewer = "auto_review";
      default_permissions = "uv-tools";
      features = {
        daemon_auto_start = true;
        fast_mode = false;
        # Codex keeps notes from its sessions, as Claude does.
        memories = true;
      };
      # How many subagents can run at once in one session.
      agents.max_concurrent_threads_per_session = 30;
      permissions.uv-tools = {
        description = "Workspace Auto with writable UV tool paths";
        extends = ":workspace";
        filesystem = {
          "~/.cache/uv" = "write";
          "~/.local/bin" = "write";
          "~/.local/share/uv/tools" = "write";
          "~/.local/share/uv/python" = "write";
        };
      };
      tui = {
        theme = "dotfiles";
        status_line = [
          "project-name"
          "git-branch"
          "model-with-reasoning"
          "context-remaining"
          "used-tokens"
          "five-hour-limit"
          "weekly-limit"
          "task-progress"
        ];
        status_line_use_colors = true;
      };
      mcp_servers.playwright = {
        command = "npx";
        args = [
          "-y"
          "@playwright/mcp@0.0.83"
          "--headless"
        ];
      };
    };
  };

  home.activation = {
    # pair's own installer, for each agent this computer has that lacks the
    # skill.
    pairStartHook = lib.hm.dag.entryAfter [ "linkGeneration" ] "run ${pairStartHook}";
    pairSkill = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      installed() { PATH="${agentPath}" command -v "$1" > /dev/null; }
      agents=""
      if installed claude && [ ! -e "$HOME/.claude/skills/pair" ]; then agents="$agents -a claude-code"; fi
      if installed codex && [ ! -e "$HOME/.agents/skills/pair" ]; then agents="$agents -a codex"; fi
      ${lib.optionalString personal ''
        # pi, opencode and Copilot CLI read the same folder as Codex.
        if [ ! -e "$HOME/.agents/skills/pair" ]; then agents="$agents -a pi -a opencode -a github-copilot"; fi
      ''}
      if [ -n "$agents" ]; then
        run env DISABLE_TELEMETRY=1 PATH="${pkgs.nodejs}/bin:${pkgs.git}/bin:$PATH" \
          npx --yes skills add RyanSaxe/pair -g -s pair $agents -y < /dev/null
      fi
    '';
  }
  // lib.optionalAttrs personal {
    agentSkills = lib.hm.dag.entryAfter [ "pairSkill" ] ''
      run /bin/sh ${linkSkills}
    '';
    codexAgents = lib.hm.dag.entryAfter [ "linkGeneration" ] "run ${lib.escapeShellArgs convertAgents}";
    piTheme = lib.hm.dag.entryAfter [ "linkGeneration" ] "run ${piTheme}";
    pairPlugins = lib.hm.dag.entryAfter [ "piTheme" ] "run ${pairPlugins}";
  };

  # Some installers put skills only in Codex's folder. This links each new
  # one for Claude as it lands.
  launchd.agents.link-agent-skills = lib.mkIf (personal && pkgs.stdenv.hostPlatform.isDarwin) {
    enable = true;
    config = {
      ProgramArguments = [
        "/bin/sh"
        linkSkills
      ];
      WatchPaths = [ "${config.home.homeDirectory}/.agents/skills" ];
      RunAtLoad = true;
    };
  };

  # The catalog installs agents only for Codex. This writes each one for
  # Claude as it lands.
  launchd.agents.convert-codex-agents = lib.mkIf (personal && pkgs.stdenv.hostPlatform.isDarwin) {
    enable = true;
    config = {
      ProgramArguments = convertAgents;
      WatchPaths = [ "${config.home.homeDirectory}/.codex/agents" ];
      RunAtLoad = true;
    };
  };
}
