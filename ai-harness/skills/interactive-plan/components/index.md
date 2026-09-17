# Editable components

Each directory contains `markup.html`, `styles.css`, and `behavior.js` only
where needed. Choose a component for the structure of the decision, not its
sample content or appearance. Copy the markup into a page and replace its
content slots and IDs. Concatenate the selected styles and behaviors into the artifact's existing
`css` and `js` inputs. There is no registration step. Custom components use the
same workflow.

| Directory                                      | Use                                         | Content and interaction                                                                                                                                                       |
| ---------------------------------------------- | ------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [comparison](comparison/markup.html)           | Two or three simultaneously visible options | Repeat the option article. Put arbitrary rich HTML in its sections. Selection uses the existing `data-choice` and `data-value` buttons.                                       |
| [choice-tabs](choice-tabs/markup.html)         | Three to seven rich, exclusive options      | Put each complete proposal in its matching panel. Tabs change the visible proposal and use the same choice state that appears in Review. Include its styles and behavior.     |
| [before-after](before-after/markup.html)       | A proposed change                           | Use the text/code viewer or the visual pair, not both by default. See the diff instructions below.                                                                            |
| [scope-checklist](scope-checklist/markup.html) | Independent inclusions                      | Repeat the checkbox row with stable option IDs and readable labels. The frame records the whole list, including untouched and empty selections. No behavior script is needed. |
| [behavior-cases](behavior-cases/markup.html)   | Situations and proposed outcomes            | Repeat the case section. Keep each ID in its contextual comment label. Revise opens the existing comment dialog.                                                              |

## Rich exclusive choices

Use choice tabs when each option needs enough room for a real preview,
proposal, or tradeoff and showing all options side by side would compress the
material. Do not use them for short labels that fit in ordinary buttons, for
independent selections, or when direct simultaneous comparison is the point.

The first panel is a preview when no draft choice exists. Selecting a tab writes
the frame's normal `data-choice` value. Selecting that tab again clears the
choice and returns to the first-panel preview. Left and Right move between tabs;
Home and End move to the first and last tabs. The tab row scrolls horizontally
when it does not fit.

Keep the card shell, tabs, focus behavior, panel visibility, and draft choice
state owned by the component. Panel content is unconstrained: do not add
component styles for its headings, grids, prototypes, or other descendants.
Each option must change material the user can judge, not merely swap an option
name over otherwise identical prose. Use three to seven options and keep every
tab's `data-value`, label, control ID, and panel value aligned.

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
