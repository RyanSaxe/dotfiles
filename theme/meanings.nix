# What each color means, for one mode. Apps ask for a meaning, such as
# `muted` or `code.function`, never a hex, so changing one here changes it
# everywhere. Catppuccin supplies every color but the four it lacks.
{ c, mode }:
let
  both = dark: light: if mode == "dark" then dark else light;
in
{
  # Surfaces, from the page out to the frame around it.
  background = c.base;
  panel = c.mantle; # a recessed area, such as a sidebar
  raised = c.surface0; # the current line, a selected row
  border = c.surface1;
  chrome = c.crust; # Rex's sidebar: the bar, the window frame
  stroke = both "#414149" "#e9e2d4"; # macOS's hairline around a window

  # Text, by how much it should be read.
  text = c.text;
  muted = c.subtext0;
  faint = c.overlay0;

  # The pair every app uses for focus, and the rarer second emphasis.
  accent = c.mauve;
  second = c.pink;

  # How something is going.
  ok = c.green;
  warn = c.yellow;
  error = c.red;
  info = c.blue;
  working = c.mauve;
  waiting = c.peach;
  done = c.green;

  # Changes, as a diff shows them.
  added = both "#60a474" "#115629";
  removed = both "#c16771" "#751e2d";
  changed = both "#6197cd" "#0e4778";

  # Code, in Neovim's tiers: one color per kind of thing.
  code = {
    function = c.peach; # anything callable
    type = c.green;
    structure = c.mauve; # keywords, operators, punctuation
    variable = c.blue;
    member = c.sky; # fields and parameters
    module = c.pink; # modules, and self or this
    constant = c.red; # constants and private names
    literal = c.subtext1; # strings and numbers stay quiet
    comment = c.overlay0;
  };

  # Markdown, as Neovim draws it through Catppuccin and render-markdown: a
  # color for each heading level, and one for each mark around the text.
  markdown = {
    headings = [
      c.red
      c.peach
      c.yellow
      c.green
      c.sapphire
      c.lavender
    ];
    code = c.green; # inline code's text
    link = c.lavender;
    url = c.blue;
    bullet = c.sky;
    quote = c.pink;
    emphasis = c.red; # bold and italic text
    rule = c.surface1;
  };

  # A repository's state, as the prompt and the agents' status line show it.
  repo = {
    folder = c.sky;
    branch = c.mauve;
    behind = c.peach; # upstream has commits you haven't pulled
    version = c.pink;
    age = c.blue;
    clean = c.green;
    dirty = c.red;
    project = c.lavender;
  };
}
