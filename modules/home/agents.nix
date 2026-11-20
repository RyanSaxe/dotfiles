# Claude Code, Codex and Antigravity CLI. Codex is on every computer, and
# Claude Code and Antigravity CLI only on a personal one: a computer without
# the personal role gets none of their files or settings. Claude Code and
# Antigravity CLI install and update themselves on both macOS and Linux, and
# Codex updates itself from its Homebrew cask on a Mac and comes from nixpkgs
# on Linux. Either way the modules only merge settings into each agent's own
# file, keeping whatever the agent writes there itself. Skills from other
# installers, such as byor, Rex and pair, stay with those tools.
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
  # Rex runs on a personal Mac and on a Linux computer that runs its server,
  # as modules/home/rex.nix sets up.
  hasRex = (personal && isDarwin) || lib.elem "rex-server" cfg.roles;
  # Where the agents' commands are, which the switch's own PATH leaves out.
  agentPath =
    if isLinux then
      "$HOME/.local/bin:${config.home.path}/bin"
    else
      "$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin";
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
    project-setup = link "ai-harness/skills/project-setup";
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

  # pair's hub wakes pi through an extension. It's registered from the
  # profile, whose path stays the same when pair updates, in place of the
  # store path `pair start` prints.
  pairAdapters = "${config.home.profileDirectory}/lib/pair/adapters";
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

  # Antigravity CLI writes its own runtime state (such as trustedWorkspaces)
  # into settings.json, so the switch merges only our managed keys.
  agyInstall = pkgs.writeShellScript "agy-install" ''
    set -eu
    if [ ! -x "$HOME/.local/bin/agy" ]; then
      script=$(mktemp)
      trap 'rm -f "$script"' EXIT
      ${pkgs.curl}/bin/curl -fsSL https://antigravity.google/cli/install.sh -o "$script"
      PATH="${pkgs.curl}/bin:${pkgs.bash}/bin:$PATH" \
        ${pkgs.bash}/bin/bash "$script" < /dev/null
    fi
  '';
  agyAllow = [
    # Mount Nix and git/theme configs read-only in the terminal sandbox so
    # sandboxed commands can run Nix binaries and read global git config.
    "read_file(/nix)"
    "read_file(${config.home.homeDirectory}/.nix-profile)"
    "read_file(${config.home.homeDirectory}/.config/git)"
    "read_file(${config.home.homeDirectory}/.config/theme)"
  ]
  ++ lib.optionals isDarwin [
    "read_file(/run/current-system)"
    "read_file(/opt/homebrew)"
  ]
  ++ [
    # Writable uv tool and cache paths, matching Codex's uv-tools profile.
    "write_file(${config.home.homeDirectory}/.cache/uv)"
    "write_file(${config.home.homeDirectory}/.local/bin)"
    "write_file(${config.home.homeDirectory}/.local/share/uv/tools)"
    "write_file(${config.home.homeDirectory}/.local/share/uv/python)"
    # IPC and network tools that run outside the sandbox in routine workflows.
    "command(pair)"
    "command(ws)"
    "command(rex)"
    "command(gh)"
    "command(git fetch)"
    "command(git pull)"
    "command(git push)"
  ];
  agyAsk = [
    "command(gh repo delete)"
    "command(git push --force)"
    "command(git push -f)"
  ];
  agySettings = pkgs.writeShellScript "agy-settings" ''
    set -eu
    jq=${pkgs.jq}/bin/jq
    settings="$HOME/.gemini/antigravity-cli/settings.json"
    mkdir -p "''${settings%/*}"
    [ -s "$settings" ] || echo '{}' > "$settings"
    "$jq" \
      --arg statusline "$HOME/.gemini/antigravity-cli/statusline.js" \
      --argjson notifications ${lib.boolToString (!hasRex)} \
      --argjson allow ${lib.escapeShellArg (builtins.toJSON agyAllow)} \
      --argjson ask ${lib.escapeShellArg (builtins.toJSON agyAsk)} \
      '
      .agentMode = "auto"
      | .allowNonWorkspaceAccess = true
      | .editorMode = "vim"
      # Opens the prompt in Insert mode, where Enter sends and shift+enter
      # or ctrl+j adds a newline.
      | .vimInsertFirst = true
      | .colorScheme = "terminal"
      | .statusLine = {type: "command", command: $statusline}
      | (if $notifications then .notifications = true else del(.notifications) end)
      | .permissions.allow = ((((.permissions.allow // []) | map(select(. != "command(gh pr merge)"))) + $allow) | unique)
      | .permissions.ask = (((.permissions.ask // []) + $ask) | unique)
      ' "$settings" > "$settings.new"
    mv "$settings.new" "$settings"
  '';
  # Merge only our named hooks so hooks from other tools, such as byor, stay.
  agyHooks = pkgs.writeShellScript "agy-hooks" ''
    set -eu
    jq=${pkgs.jq}/bin/jq
    hooks="$HOME/.gemini/config/hooks.json"
    mkdir -p "''${hooks%/*}"
    [ -s "$hooks" ] || echo '{}' > "$hooks"
    "$jq" \
      --arg pushover ${lib.escapeShellArg (pushover "Antigravity")} \
      --arg pair ${lib.escapeShellArg pairRegister} \
      '
      .["pushover-notify"] = {
        Stop: [{type: "command", command: $pushover}]
      }
      | .["pair-register"] = {
        PreInvocation: [{type: "command", command: $pair}]
      }
    ' "$hooks" > "$hooks.new"
    mv "$hooks.new" "$hooks"
  '';
  # Rex and tmux take ctrl+k to move between panes and alt+s for the ws
  # sessions picker, so those two Antigravity actions move to free keys.
  # Antigravity writes its other defaults into the file itself.
  agyKeybindings = pkgs.writeShellScript "agy-keybindings" ''
    set -eu
    jq=${pkgs.jq}/bin/jq
    keybindings="$HOME/.gemini/antigravity-cli/keybindings.json"
    mkdir -p "''${keybindings%/*}"
    [ -s "$keybindings" ] || echo '{}' > "$keybindings"
    "$jq" '
      .["subagent.approve_fast"] = ["alt+k"]
      | .["swarm.board"] = ["alt+b"]
    ' "$keybindings" > "$keybindings.new"
    mv "$keybindings.new" "$keybindings"
  '';
in
lib.mkIf (lib.elem "base" cfg.roles) {
  home.packages = [ pair ];

  home.file = {
    ".codex/themes/dotfiles.tmTheme".source =
      config.lib.file.mkOutOfStoreSymlink "${config.xdg.configHome}/theme/Dotfiles.tmTheme";
  }
  // lib.optionalAttrs personal (
    {
      # Claude reads the instructions through an import, and Antigravity
      # directly through a symlink. Codex can't import, so it gets them
      # through developer_instructions below.
      ".claude/CLAUDE.md".text = ''
        @${cfg.repo}/ai-harness/AGENTS.md
      '';
      ".claude/statusline.js".source = link "ai-harness/statusline.js";
      ".claude/themes/dotfiles.json".source =
        config.lib.file.mkOutOfStoreSymlink "${config.xdg.configHome}/theme/claude-theme.json";
      ".gemini/config/AGENTS.md".source = link "ai-harness/AGENTS.md";
      ".gemini/antigravity-cli/statusline.js".source = link "ai-harness/statusline.js";
    }
    // skillLinks ".claude/skills"
    // skillLinks ".gemini/config/skills"
  )
  // {
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
    enable = personal;
    package = null;
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
      # The bell marks the agent's tmux window when a turn ends or a prompt
      # waits, which is how ws learns in tmux that an agent needs you.
      preferredNotifChannel = "terminal_bell";
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
        vim_mode_default = true;
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
      }
      # Without Rex, Codex rings the bell for every notification, which
      # covers a finished turn, an approval and a question, whether or not
      # its pane has focus. tmux marks the bell on a window you aren't
      # viewing, and ws reads that as the agent needing you.
      // lib.optionalAttrs (!hasRex) {
        notification_method = "bel";
        notifications = true;
        notification_condition = "always";
      };
      mcp_servers.playwright = {
        command = "npx";
        args = [
          "-y"
          "@playwright/mcp@0.0.83"
          "--headless"
          "--isolated"
          "--output-dir"
          "${config.xdg.stateHome}/codex/browser-artifacts/playwright"
        ];
      };
    };
  };

  home.activation = {
    # pair's own installer, for each agent this computer has that lacks the
    # skill.
    pairStartHook = lib.mkIf personal (
      lib.hm.dag.entryAfter [ "linkGeneration" ] "run ${pairStartHook}"
    );
    pairSkill = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      installed() { PATH="${agentPath}" command -v "$1" > /dev/null; }
      agents=""
      ${lib.optionalString personal ''if installed claude && [ ! -e "$HOME/.claude/skills/pair" ]; then agents="$agents -a claude-code"; fi''}
      if installed codex && [ ! -e "$HOME/.agents/skills/pair" ]; then agents="$agents -a codex"; fi
      # Copilot CLI, and pi on a personal computer, read the same folder as
      # Codex.
      if [ ! -e "$HOME/.agents/skills/pair" ]; then agents="$agents -a github-copilot${lib.optionalString personal " -a pi"}"; fi
      if [ -n "$agents" ]; then
        run env DISABLE_TELEMETRY=1 PATH="${pkgs.nodejs}/bin:${pkgs.git}/bin:$PATH" \
          npx --yes skills add RyanSaxe/pair -g -s pair $agents -y < /dev/null
      fi
    '';
  }
  // lib.optionalAttrs personal {
    agyInstall = lib.hm.dag.entryAfter [ "writeBoundary" ] "run ${agyInstall}";
    agySettings = lib.hm.dag.entryAfter [ "linkGeneration" ] "run ${agySettings}";
    agyHooks = lib.hm.dag.entryAfter [ "linkGeneration" ] "run ${agyHooks}";
    agyKeybindings = lib.hm.dag.entryAfter [ "linkGeneration" ] "run ${agyKeybindings}";
    agentSkills = lib.hm.dag.entryAfter [ "pairSkill" ] ''
      run /bin/sh ${linkSkills}
    '';
    codexAgents = lib.hm.dag.entryAfter [ "linkGeneration" ] "run ${lib.escapeShellArgs convertAgents}";
    piTheme = lib.hm.dag.entryAfter [ "linkGeneration" ] "run ${piTheme}";
    pairPlugins = lib.hm.dag.entryAfter [ "piTheme" ] "run ${pairPlugins}";
  };

  # Some installers put skills only in Codex's folder. This links each new
  # one for Claude Code and Antigravity CLI as it lands.
  launchd.agents.link-agent-skills = lib.mkIf (personal && isDarwin) {
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
  # Claude Code and Antigravity CLI as it lands.
  launchd.agents.convert-codex-agents = lib.mkIf (personal && isDarwin) {
    enable = true;
    config = {
      ProgramArguments = convertAgents;
      WatchPaths = [ "${config.home.homeDirectory}/.codex/agents" ];
      RunAtLoad = true;
    };
  };
}
