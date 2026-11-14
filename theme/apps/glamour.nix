# A glamour style, which ws's popups and gh render Markdown with. It draws
# Markdown as Neovim does: each heading with its #s in its level's color on
# a band of that color, inline code on the raised color, and code in
# Neovim's tiers.
{
  lib,
  t,
  wash,
  ...
}:
let
  md = t.markdown;
  code = t.code;
  fg = color: { inherit color; };
  heading =
    level:
    let
      color = lib.elemAt md.headings (level - 1);
    in
    {
      prefix = lib.concatStrings (lib.replicate level "#") + " ";
      suffix = " ";
      inherit color;
      # render-markdown's band, which Catppuccin mixes at this amount.
      background_color = wash 0.095 color;
    };
in
{
  "glamour.json" = builtins.toJSON {
    document = {
      block_prefix = "\n";
      block_suffix = "\n";
      color = t.text;
      margin = 2;
    };
    block_quote = {
      color = md.quote;
      indent = 1;
      indent_token = "▋ ";
    };
    paragraph = { };
    list.level_indent = 2;
    heading.block_suffix = "\n";
    h1 = heading 1;
    h2 = heading 2;
    h3 = heading 3;
    h4 = heading 4;
    h5 = heading 5;
    h6 = heading 6;
    text = { };
    strikethrough.crossed_out = true;
    emph = {
      color = md.emphasis;
      italic = true;
    };
    strong = {
      color = md.emphasis;
      bold = true;
    };
    hr = {
      color = md.rule;
      format = "\n────────\n";
    };
    item.block_prefix = "• ";
    enumeration.block_prefix = ". ";
    task = {
      ticked = "[✓] ";
      unticked = "[ ] ";
    };
    link = {
      color = md.url;
      underline = true;
    };
    link_text.color = md.link;
    image = {
      color = md.url;
      underline = true;
    };
    image_text = {
      color = md.link;
      format = "Image: {{.text}} →";
    };
    code = {
      color = md.code;
      background_color = t.raised;
    };
    code_block = {
      color = t.text;
      margin = 2;
      # The tiers bat.nix gives each grammar's scopes, in Chroma's names.
      chroma =
        lib.mapAttrs (_: fg) {
          text = t.text;
          error = t.error;
          comment = code.comment;
          comment_preproc = code.structure;
          keyword = code.structure;
          keyword_reserved = code.structure;
          keyword_namespace = code.structure;
          keyword_type = code.type;
          operator = code.structure;
          punctuation = code.structure;
          name = code.variable;
          name_builtin = code.function;
          name_tag = code.type;
          name_attribute = code.member;
          name_class = code.type;
          name_constant = code.constant;
          name_decorator = code.constant;
          name_exception = code.type;
          name_function = code.function;
          name_other = code.variable;
          literal = code.literal;
          literal_number = code.literal;
          literal_date = code.literal;
          literal_string = code.literal;
          literal_string_escape = code.module;
          generic_deleted = t.removed;
          generic_inserted = t.added;
          generic_subheading = t.faint;
        }
        // {
          comment = {
            color = code.comment;
            italic = true;
          };
          generic_emph.italic = true;
          generic_strong.bold = true;
        };
    };
    table = { };
    definition_list = { };
    definition_term = { };
    definition_description.block_prefix = "\n🠶 ";
    html_block = { };
    html_span = { };
  };
}
