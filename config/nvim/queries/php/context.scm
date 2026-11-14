;; extends

(anonymous_function
  body: (_
    (_) @context.end)) @context

(arrow_function
  body: (_) @context.end) @context

(match_expression
  body: (_
    (_) @context.end)) @context

(enum_declaration
  name: (_) @context.start
  body: (_
    (_) @context.end)) @context

(interface_declaration
  name: (_) @context.start
  body: (_
    (_) @context.end)) @context

(trait_declaration
  name: (_) @context.start
  body: (_
    (_) @context.end)) @context
