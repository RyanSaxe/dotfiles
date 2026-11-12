# bat's syntax theme, which delta and Codex share. It gives code Neovim's
# tiers: each code color takes the grammar scopes listed for it.
{
  lib,
  t,
  c,
  ...
}:
let
  scopes = {
    variable = "variable, variable.other, variable.other.readwrite, variable.other.object, source.python";
    comment = "comment, punctuation.definition.comment, comment.block.documentation, comment.line.documentation, string.quoted.docstring";
    literal = "string, punctuation.definition.string, constant.numeric, constant.language.boolean, constant.language.false, constant.language.true, constant.language.none, constant.language.null";
    constant = "variable.other.constant, entity.name.constant, constant.other, variable.private, meta.annotation, meta.decorator, punctuation.decorator, entity.name.function.decorator";
    structure = "keyword, keyword.control, keyword.operator, keyword.operator.word, storage, storage.type, storage.modifier, operator, punctuation, punctuation.accessor, punctuation.separator, punctuation.definition, meta.function.parameters punctuation";
    function = "entity.name.function, variable.function, support.function, support.function.builtin, meta.function-call, meta.function-call.method";
    type = "entity.name.class, entity.name.type, entity.name.struct, support.class, support.type, meta.type, storage.type.class, meta.function-call.constructor, markup.heading, entity.name.tag, entity.name.tag.html, entity.name.tag.xml";
    member = "variable.parameter, meta.function.parameters, variable.other.member, variable.object.property, meta.property.object, support.type.property-name, entity.name.tag.yaml, support.type.property-name.json, meta.mapping.key, entity.other.attribute-name";
    module = "constant.character.escape, string constant.character, entity.name.namespace, support.other.namespace, support.other.module, entity.name.import, variable.language.this, variable.language.self, variable.language.super";
  };
  rule = scope: color: style: {
    inherit scope;
    settings = {
      foreground = color;
    }
    // lib.optionalAttrs (style != null) { fontStyle = style; };
  };
in
{
  "Dotfiles.tmTheme" = lib.generators.toPlist { escape = true; } {
    name = "Dotfiles";
    settings = [
      {
        settings = {
          background = t.background;
          foreground = t.text;
          caret = t.accent;
          lineHighlight = t.raised;
          selection = "${c.overlay2}4d";
          activeGuide = t.border;
          findHighlight = t.code.member;
          gutterForeground = t.faint;
          misspelling = t.error;
        };
      }
      (rule "text, source" t.text null)
    ]
    ++ lib.mapAttrsToList (
      kind: scope: rule scope t.code.${kind} (if kind == "comment" then "italic" else null)
    ) scopes
    ++ [
      (rule "markup.bold" t.code.function "bold")
      (rule "markup.italic" t.code.member "italic")
      (rule "invalid, invalid.illegal, invalid.deprecated, markup.deleted" t.error "bold")
    ];
  };
}
