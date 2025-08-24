; extends
(
  (identifier) @keyword.risky
  (#match? @keyword.risky "^(exec|eval)$")
  (#set! priority 150)
)

[
  "assert"
  "raise"
  "except"
] @keyword.error
(#set! priority 150)

(
  (identifier) @variable.private
  (#match? @variable.private "^_{1,2}[^_].*[^_]$")
  (#set! priority 150)
)

