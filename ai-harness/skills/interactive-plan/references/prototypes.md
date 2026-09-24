# Prototypes

A prototype preserves an approved interaction exactly, so the implementer
sees the behavior instead of a description of it.

| Field  | Contract                                                                 |
| ------ | ------------------------------------------------------------------------ |
| id     | Unique stable ID with the same character rules as page IDs.              |
| title  | Accessible, descriptive title, shown in the embed's header.              |
| html   | Complete self-contained HTML document, including its styles and scripts. |
| file   | Page-source alternative to html, resolved relative to the page JSON.     |
| height | Positive preview height in pixels.                                       |

Put prototypes in their owning page's `prototypes` array. IDs are unique
within that revision. Put `data-prototype="ID"` on the element where the
prototype belongs. The
frame renders it with a header that has the title, a Source toggle that
shows the exact source with syntax highlighting, and an Open full size
button that shows the document alone in a new tab. The document runs in a
sandboxed iframe with no same-origin access to the review frame, so its
controls cannot submit real feedback. Scripts, forms, and popup links work
inside the sandbox. The embed is transparent: the document paints its own
background and should follow the viewer's theme with a
`prefers-color-scheme` rule.

An embed is about 780px wide. A component mock renders at its natural width
without scaling. A layout mock designed wider than the embed collapses
unless it scales. Give it a stage at the design width (1120 works for a
three-column layout) with `transform: scale(min(1, innerWidth / 1120))`
and a control to switch to 100%, and use Open full size to see it at real
size.
