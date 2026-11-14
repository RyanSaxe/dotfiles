;; extends

(mixin_declaration
  (class_body) @context.end) @context

(enum_declaration
  body: (_) @context.end) @context

(declaration
  [
    (constructor_signature)
    (constant_constructor_signature)
  ] @context.final) @context

(function_expression
  body: (function_expression_body
    (block) @context.end)) @context
