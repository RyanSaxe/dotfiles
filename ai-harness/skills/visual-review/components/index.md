# Components

Each directory holds a `markup.html` to copy into a page, and a helper
script where one exists. [authoring.md](../references/authoring.md)
documents the same markup. The frame's stylesheet already styles all of
it; nothing needs to be included or registered.

| Directory                            | Use                                                                          |
| ------------------------------------ | ---------------------------------------------------------------------------- |
| [diagram](diagram/markup.html)       | Any Mermaid diagram with labels that carry markup and nodes that open pages. |
| [code-block](code-block/markup.html) | Real lines from the repository at the document's ref, notes interleaved.     |
| [diff](diff/markup.html)             | A change to one file in the Pierre viewer; `diff.mjs` makes its input.       |
| [figure](figure/markup.html)         | A chart, an equation, or a figure with controls a reader can move.           |
