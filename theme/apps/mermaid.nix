# mmdc's config for one mode, which snacks.nvim passes it when it draws a
# Mermaid diagram in a note. A box is the raised color with the info color
# around it and the text color inside, and a line is the muted color.
{ t, ... }:
{
  "mermaid.json" = builtins.toJSON {
    theme = "base";
    themeVariables = {
      background = t.background;
      primaryColor = t.raised;
      primaryTextColor = t.text;
      primaryBorderColor = t.info;
      lineColor = t.muted;
      secondaryColor = t.border;
      tertiaryColor = t.panel;
      fontFamily = "Menlo";
    };
  };
}
