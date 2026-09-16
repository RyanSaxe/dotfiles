# Editable components

Each directory contains `markup.html`, `styles.css`, and `behavior.js` only
where needed. Copy the markup into a page and replace its content slots and IDs.
Concatenate the selected styles and behaviors into the artifact's existing
`css` and `js` inputs. There is no registration step. Custom components use the
same workflow.

| Directory                                      | Use                              | Content and interaction                                                                                                                                                            |
| ---------------------------------------------- | -------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [comparison](comparison/markup.html)           | Two or three alternatives        | Repeat the option article. Put arbitrary rich HTML in its sections. Selection uses the existing `data-choice` and `data-value` buttons.                                            |
| [before-after](before-after/markup.html)       | A proposed change                | Use the text/code viewer or the visual pair, not both by default. See the diff instructions below.                                                                                 |
| [scope-checklist](scope-checklist/markup.html) | Independent inclusions           | Repeat the scope row with stable IDs and labels. The checkbox records Include or Defer through the existing draft. Untouched items remain unanswered. Include its behavior script. |
| [behavior-cases](behavior-cases/markup.html)   | Situations and proposed outcomes | Repeat the case section. Keep each ID in its contextual comment label. Revise opens the existing comment dialog.                                                                   |

## Rich comparisons

Matched sections align by default. Set `--comparison-rows` to the number of
direct children per option, including header and footer. Use
`data-layout="independent"` for options with different content structures.
Columns stack when they no longer fit. Keep selection separate from links,
charts, and other interactive content inside an option.

## Before and after

For text/code, generate the input with Git:

```sh
node components/before-after/diff.mjs BEFORE AFTER OUTPUT.json
```

HTML-escape that JSON into the markup's `textarea[data-diff-input]`. The helper
preserves both UTF-8 source strings and a unified Git patch. It requires Git
and refuses to overwrite an existing output. Include `behavior.js` and
`styles.css`; the frame loads the pinned Pierre viewer only when needed.

The viewer uses the same `github-light` and `github-dark` themes as other Shiki
code. Its layout switch is a viewing preference, not a planning choice.
Rendering requires network access. Failures are reported without an offline
renderer. Exact sources and the patch remain in the artifact.

For visual changes, fill the before/proposed HTML slots and explain the changes
in the legend. Apply `added`, `removed`, or `changed` classes to changed content
or Mermaid nodes. Do not set fixed colors in Mermaid `classDef` declarations;
the component supplies theme-aware colors. These annotations express the
author's meaning, not an inferred text diff.
