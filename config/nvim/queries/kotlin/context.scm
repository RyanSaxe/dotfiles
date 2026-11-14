;; extends

(getter
  (function_body
    (_) @context.end)) @context

(setter
  (function_body
    (_) @context.end)) @context

(object_declaration
  (class_body
    (_)) @context.end) @context

(companion_object
  (class_body
    (_)) @context.end) @context

(lambda_literal
  (statements) @context.end) @context

(anonymous_initializer
  (statements) @context.end) @context
