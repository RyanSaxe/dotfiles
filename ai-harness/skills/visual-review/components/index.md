# Components

Each directory holds a `markup.html` to copy into a page and, where one
exists, a helper. The markup contracts are in
[authoring.md](../references/authoring.md); these are the same contracts
as files an agent can copy. Styles ship in the frame, so there is nothing
to include and no registration step.

| Directory                            | Use                                                                          |
| ------------------------------------ | ---------------------------------------------------------------------------- |
| [diagram](diagram/markup.html)       | Any Mermaid diagram with labels that carry markup and nodes that open pages. |
| [code-block](code-block/markup.html) | Real lines from the repository at the document's ref, notes interleaved.     |
| [diff](diff/markup.html)             | A change to one file in the Pierre viewer; `diff.mjs` makes its input.       |
