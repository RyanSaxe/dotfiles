;; extends

(record_declaration
  body: (_) @context.end) @context

(interface_declaration
  body: (_) @context.end) @context

(enum_declaration
  body: (_) @context.end) @context

(constructor_declaration
  body: (_) @context.end) @context

(compact_constructor_declaration
  body: (_) @context.end) @context

(lambda_expression
  body: (block) @context.end) @context

(try_statement
  body: (_) @context.end) @context

(try_with_resources_statement
  body: (_) @context.end) @context

(catch_clause
  body: (_) @context.end) @context

(finally_clause
  (block) @context.end) @context
