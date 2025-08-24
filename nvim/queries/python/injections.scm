; extends
; commenting everything out for now since this doesnt work on function or class docstrings due to indentation
; Only match standalone string expressions (i.e. docstrings)
; (
;   (expression_statement
;      (string) @injection.content
;   )
;   ; 1) Re-parse as markdown…
;   (#set! injection.language "markdown")
;   ; 2) Include all child nodes (this way the actual markdown gets parsed)
;   (#set! injection.include-children true)
; )
