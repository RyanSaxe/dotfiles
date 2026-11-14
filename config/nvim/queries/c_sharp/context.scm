;; extends

(property_declaration
  accessors: (_) @context.end) @context

(accessor_declaration
  body: (block) @context.end) @context

(switch_expression
  "{" @context.end) @context

(lambda_expression
  body: (block) @context.end) @context

(local_function_statement
  body: (_) @context.end) @context
