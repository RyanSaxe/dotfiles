# bat's syntax theme, which delta and Codex share. It gives code Neovim's
# tiers: each code color takes the grammar scopes listed for it.
{
  lib,
  t,
  c,
  wash,
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
      (rule "invalid, invalid.illegal, invalid.deprecated, markup.deleted" t.error "bold")
    ]
    # Markdown in the colors Neovim draws it in. bat's grammar numbers only
    # the first two heading levels, so the rest share the third's color.
    ++ (
      let
        md = t.markdown;
        heading = lib.elemAt md.headings;
      in
      [
        (rule "markup.heading.1, markup.heading.1 punctuation" (heading 0) null)
        (rule "markup.heading.2, markup.heading.2 punctuation" (heading 1) null)
        (rule "markup.heading.markdown, markup.heading.markdown punctuation" (heading 2) null)
        (rule "markup.raw.inline" md.code null)
        (rule "meta.link.inline.description, meta.link.reference.description, meta.image.inline.description"
          md.link
          null
        )
        (rule "markup.underline.link" md.url null)
        (rule "punctuation.definition.list_item" md.bullet null)
        (rule "markup.quote, punctuation.definition.blockquote" md.quote null)
        (rule "markup.bold" md.emphasis "bold")
        (rule "markup.italic" md.emphasis "italic")
        (rule "punctuation.definition.thematic-break" md.rule null)
      ]
    )
    # Codex paints the lines of every edit it shows with these backgrounds,
    # which are Neovim's row colors. bat ignores a scope's background.
    ++
      lib.mapAttrsToList
        (scope: color: {
          inherit scope;
          settings.background = wash 0.2 color;
        })
        {
          "markup.inserted" = t.added;
          "markup.deleted" = t.removed;
        };
  };
}
