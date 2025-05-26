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
