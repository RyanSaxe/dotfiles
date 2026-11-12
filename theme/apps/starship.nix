# The prompt, from config/zsh/starship.toml, with the palette its color
# names come from. The agents' status line shows the same facts in the same
# colors.
{ lib, t, ... }:
let
  palette = {
    faint = t.faint;
    inherit (t.repo)
      folder
      branch
      behind
      version
      age
      clean
      dirty
      project
      ;
    ok = t.ok;
    error = t.error;
    caret = t.accent;
    caret_vi = t.code.structure;
  };
in
{
  "starship.toml" = builtins.readFile ../../config/zsh/starship.toml + ''

    [palettes.theme]
    ${lib.concatLines (lib.mapAttrsToList (name: color: ''${name} = "${color}"'') palette)}'';
}
