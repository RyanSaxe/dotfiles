# pi's theme for one mode. The agents module links each mode's file into
# ~/.pi/agent/themes, and pi picks the one for the background the terminal
# reports.
{
  t,
  wash,
  mode,
  ...
}:
let
  md = t.markdown;
  code = t.code;
in
{
  "pi-theme.json" = builtins.toJSON {
    "$schema" = "https://pi.dev/schemas/theme.schema.json";
    name = "dotfiles-${mode}";
    appearance = mode;
    colors = {
      accent = t.accent;
      border = t.border;
      borderAccent = t.accent;
      borderMuted = t.raised;
      success = t.ok;
      error = t.error;
      warning = t.warn;
      muted = t.muted;
      dim = t.faint;
      text = t.text;
      thinkingText = t.muted;
      selectedBg = t.raised;
      searchMatchBg = wash 0.3 code.member; # Neovim's Search
      userMessageBg = t.raised;
      userMessageText = t.text;
      customMessageBg = wash 0.2 t.second;
      customMessageText = t.muted;
      customMessageLabel = t.second;
      toolPendingBg = wash 0.2 t.faint;
      toolSuccessBg = wash 0.2 t.ok;
      toolErrorBg = wash 0.2 t.error;
      toolTitle = t.text;
      toolOutput = t.muted;

      mdHeading = builtins.head md.headings;
      mdLink = md.link;
      mdLinkUrl = md.url;
      mdCode = md.code;
      mdCodeBlock = t.text;
      mdCodeBlockBorder = t.faint;
      mdQuote = md.quote;
      mdQuoteBorder = md.quote;
      mdHr = md.rule;
      mdListBullet = md.bullet;

      toolDiffAdded = t.added;
      toolDiffRemoved = t.removed;
      toolDiffContext = t.muted;

      syntaxComment = code.comment;
      syntaxKeyword = code.structure;
      syntaxFunction = code.function;
      syntaxVariable = code.variable;
      syntaxString = code.literal;
      syntaxNumber = code.literal;
      syntaxType = code.type;
      syntaxOperator = code.structure;
      syntaxPunctuation = code.structure;

      # The input's border at each thinking level, from off to max.
      thinkingOff = t.faint;
      thinkingMinimal = t.muted;
      thinkingLow = t.info;
      thinkingMedium = t.accent;
      thinkingHigh = t.second;
      thinkingXhigh = t.waiting;
      thinkingMax = t.error;
      bashMode = t.second;
    };
  };
}
