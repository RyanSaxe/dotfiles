# Claude Code's custom theme. `base` is the built-in theme Claude starts
# from, and the overrides set every token it has. Claude reads the theme
# from ~/.claude/themes, where the agents module links this file. Token
# names can mislead, so each comment says what the token colors.
#
# The theme can't color code. Claude colors a fenced block's syntax with
# the terminal's ANSI colors, and a diff's or a file's syntax with fixed
# themes of its own. Its Markdown takes colors from the base theme alone,
# so inline code, and a fence that names no language, keep the base's
# `permission` color.
{
  t,
  c,
  mode,
  wash,
  ...
}:
let
  # Claude sweeps a second color across animated text, which here is the
  # text color.
  shimmer = t.text;
in
{
  "claude-theme.json" = builtins.toJSON {
    name = "Dotfiles";
    base = mode;
    overrides = {
      # Text, by how much it should be read.
      text = t.text;
      inactive = t.muted; # secondary text, and the mark before a sent message
      subtle = t.faint; # dashed rules, queued and skipped marks
      inverseText = t.background; # text on a filled label

      # Surfaces.
      userMessageBackground = t.raised; # the band behind a sent message, a selected row
      userMessageBackgroundHover = t.border; # a hovered or expanded message
      selectionBg = t.border; # text selected with the mouse
      composerSidebarBackground = t.panel; # a panel docked beside the prompt
      bashMessageBackgroundColor = wash 0.2 t.second; # a sent `!` command
      memoryBackgroundColor = wash 0.2 t.info; # a note saved to memory
      promptBorder = t.border; # the rules above and below the prompt
      bashBorder = t.second; # those rules, and the `!`, in shell mode

      # Focus and Claude itself.
      claude = t.accent; # the spinner, and Claude's own marks
      claudeShimmer = shimmer;
      clawd_body = t.accent; # the mascot
      clawd_background = t.background; # the mascot's eyes
      briefLabelClaude = t.accent;
      briefLabelYou = t.info;
      permission = t.accent; # dialogs, such as a permission request
      permissionShimmer = shimmer;
      suggestion = t.info; # suggested commands, list pointers, info marks
      remember = t.info; # a saved memory's `#`
      ide = t.info; # a label at the start of the prompt, notes below it
      professionalBlue = t.info; # the help dialog
      chromeYellow = t.warn; # Claude in Chrome's dialogs
      skill = t.second; # a skill's label in the command list
      effortUltra = t.second; # ultracode
      rate_limit_fill = t.info; # usage bars
      rate_limit_empty = t.border;
      promptBorderShimmer = shimmer;
      inactiveShimmer = shimmer;

      # How something is going.
      background = t.working; # background and remote work, and an agent's label in the command list
      claudeBlue_FOR_SYSTEM_SPINNER = t.info; # the spinner while hooks run
      claudeBlueShimmer_FOR_SYSTEM_SPINNER = shimmer;
      success = t.ok;
      error = t.error; # also the mode that bypasses permissions
      warning = t.warn; # also auto mode
      warningShimmer = shimmer;
      merged = t.done; # a merged pull request
      fastMode = t.warn;
      fastModeShimmer = shimmer;

      # Permission modes, from safest to riskiest: plan, accept edits, auto,
      # bypass.
      planMode = t.info;
      autoAccept = t.ok;
      autoAcceptShimmer = shimmer;

      # A diff's rows, its changed words, and the +N and -N counts, which
      # take the word colors.
      diffAdded = wash 0.2 t.added;
      diffRemoved = wash 0.2 t.removed;
      diffAddedDimmed = wash 0.1 t.added;
      diffRemovedDimmed = wash 0.1 t.removed;
      diffAddedWord = t.added;
      diffRemovedWord = t.removed;

      # The colors an agent can be given, by name.
      red_FOR_SUBAGENTS_ONLY = c.red;
      orange_FOR_SUBAGENTS_ONLY = c.peach;
      yellow_FOR_SUBAGENTS_ONLY = c.yellow;
      green_FOR_SUBAGENTS_ONLY = c.green;
      cyan_FOR_SUBAGENTS_ONLY = c.sky;
      blue_FOR_SUBAGENTS_ONLY = c.blue;
      purple_FOR_SUBAGENTS_ONLY = c.mauve;
      pink_FOR_SUBAGENTS_ONLY = c.pink;

      # The letters of "ultrathink" in the prompt.
      rainbow_red = c.red;
      rainbow_orange = c.peach;
      rainbow_yellow = c.yellow;
      rainbow_green = c.green;
      rainbow_blue = c.blue;
      rainbow_indigo = c.lavender;
      rainbow_violet = c.mauve;
      rainbow_red_shimmer = shimmer;
      rainbow_orange_shimmer = shimmer;
      rainbow_yellow_shimmer = shimmer;
      rainbow_green_shimmer = shimmer;
      rainbow_blue_shimmer = shimmer;
      rainbow_indigo_shimmer = shimmer;
      rainbow_violet_shimmer = shimmer;
    };
  };
}
