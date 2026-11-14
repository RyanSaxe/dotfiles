# Claude Code and Codex. On a Mac both install and update themselves, so
# their modules have no package. Linux installs them from nixpkgs, and
# Claude Code only on a personal computer. Either way the modules only
# merge settings into each agent's own file, keeping whatever the agent
# writes there itself. ~/.codex/AGENTS.md
# is yours, so it never comes from the repo. Skills from other installers,
# such as byor, Rex and pair, stay with those tools.
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
  inherit (pkgs.stdenv.hostPlatform) isLinux;
  # Where the agents' commands are, which the switch's own PATH leaves out.
  agentPath =
    if isLinux then "${config.home.path}/bin" else "$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin";
  linkSkills = "${cfg.repo}/ai-harness/tools/link-agent-skills.sh";

  skills.worktrees = link "ai-harness/skills/worktrees";
  skillLinks =
    dir: lib.mapAttrs' (name: source: lib.nameValuePair "${dir}/${name}" { inherit source; }) skills;

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
    # Claude reads both instruction files through imports. Codex can't
    # import, so it gets the repo's through developer_instructions below.
    ".claude/CLAUDE.md".text = ''
      @${cfg.repo}/ai-harness/AGENTS.md
      @${config.home.homeDirectory}/.codex/AGENTS.md
    '';
    ".claude/references".source = link "ai-harness/references";
    ".claude/statusline.js".source = link "ai-harness/statusline.js";
    ".codex/references".source = link "ai-harness/references";
    ".codex/themes/dotfiles.tmTheme".source =
      config.lib.file.mkOutOfStoreSymlink "${config.xdg.configHome}/theme/Dotfiles.tmTheme";
  }
  // skillLinks ".claude/skills"
  // skillLinks ".agents/skills";

  # Codex reads its managed hooks from /etc/codex, which Home Manager can't
  # write. A Linux computer links that folder to these files once:
  #   sudo ln -sfn ~/.config/codex/managed /etc/codex
  xdg.configFile = lib.mkIf isLinux (
    lib.mapAttrs' (
      name: source:
      lib.nameValuePair "codex/managed/${name}" {
        source = if builtins.isPath source then source else config.lib.file.mkOutOfStoreSymlink source;
      }
    ) (import ../codex-managed.nix cfg.repo)
  );

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
      # Codex adds these to ~/.codex/AGENTS.md, so an edit to the repo's
      # file reaches Codex at the next home switch.
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
    # Claude's import needs the file, and the switch that drops the old link
    # leaves none. From then on the file is yours.
    codexInstructions = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      if [ ! -e "$HOME/.codex/AGENTS.md" ]; then
        run rm -f "$HOME/.codex/AGENTS.md"
        run touch "$HOME/.codex/AGENTS.md"
      fi
    '';
    # pair's own installer, for each agent this computer has that lacks the
    # skill.
    pairSkill = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      installed() { PATH="${agentPath}" command -v "$1" > /dev/null; }
      agents=""
      if installed claude && [ ! -e "$HOME/.claude/skills/pair" ]; then agents="$agents -a claude-code"; fi
      if installed codex && [ ! -e "$HOME/.agents/skills/pair" ]; then agents="$agents -a codex"; fi
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
}
