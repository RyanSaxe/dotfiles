; extends
(
  (identifier) @keyword.risky
  (#any-of? @keyword.risky "exec" "eval")
  (#set! priority 150)
)

([
  "assert"
  "raise"
  "except"
] @keyword.error
  (#set! priority 150))

; Leading-underscore names, excluding sunders/dunders like __init__.
(
  (identifier) @variable.private
  (#match? @variable.private "\\v^_{1,2}([^_].*)?[^_]$")
  (#set! priority 150)
)
