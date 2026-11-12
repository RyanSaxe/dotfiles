# Claude Code and Codex. Both install and update themselves, so their
# modules have no package and only merge settings into each agent's own
# file, keeping whatever the agent writes there itself. ~/.codex/AGENTS.md
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
  linkSkills = "${cfg.repo}/ai-harness/tools/link-agent-skills.sh";

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
  };

  programs.claude-code = {
    enable = true;
    package = null;
    mutableSettings = true;
    settings = {
      model = "opus[1m]";
      effortLevel = "xhigh";
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
    package = null;
    mutableSettings = true;
    settings = {
      model = "gpt-6-luna";
      model_reasoning_effort = "xhigh";
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
      };
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
    # skill. The switch's PATH has none of the agents' folders.
    pairSkill = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      installed() { PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin" command -v "$1" > /dev/null; }
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
