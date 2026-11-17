# delta's colors, which git's config includes. The code takes bat's theme
# for this mode, named here because delta doesn't read bat's config. The
# diff colors match Neovim's: a changed line takes a fifth of its diff color
# over the background, the words that changed take 0.46 of it, and both
# keep their syntax colors.
{
  lib,
  t,
  mode,
  wash,
  ...
}:
let
  style = amount: color: "syntax ${wash amount color}";
in
{
  "delta-colors.gitconfig" = lib.generators.toGitINI {
    delta = {
      syntax-theme = "dotfiles-${mode}";
      minus-style = style 0.2 t.removed;
      minus-emph-style = style 0.46 t.removed;
      plus-style = style 0.2 t.added;
      plus-emph-style = style 0.46 t.added;
      # git blame bands each commit's lines in the next of these.
      blame-palette = "${t.background} ${t.panel} ${t.raised}";
    };
  };
}
