# Editable components

Each directory contains `markup.html`, `styles.css`, and `behavior.js` only
where needed. Choose a component for the structure of the decision, not its
sample content or appearance. Copy the markup into a page and replace its
content slots and IDs. Concatenate the selected styles and behaviors into the
artifact's existing `css` and `js` inputs. There is no registration step.
Custom components use the same workflow.

| Directory                                      | Use                                              | Content and interaction                                                                                                                                                       |
| ---------------------------------------------- | ------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [decision](decision/markup.html)               | Two to five text options                         | Radio-style rows; each row is the `data-value` button with a title, an optional Recommended tag, and one line of consequence. No behavior script.                             |
| [visual-decision](visual-decision/markup.html) | Options that each need a visual                  | Option articles with a header, one line, and a figure. Renders as columns or tabs by width and count; a toggle overrides. Include its styles and behavior.                    |
| [question](question/markup.html)               | An open answer the agent needs                   | A card with a stripe, the question, why it matters, and a textarea. The answer travels with feedback as `groups.answers`. No behavior script.                                 |
| [comparison](comparison/markup.html)           | Two or three simultaneously visible rich options | Repeat the option article. Put arbitrary rich HTML in its sections. Selection uses the existing `data-choice` and `data-value` buttons.                                       |
| [choice-tabs](choice-tabs/markup.html)         | Three to seven rich, exclusive options           | Put each complete proposal in its matching panel. Tabs change the visible proposal and use the same choice state that appears in Feedback. Include its styles and behavior.   |
| [before-after](before-after/markup.html)       | A proposed change                                | Use the text/code viewer or the visual pair, not both by default. See the diff instructions below.                                                                            |
| [scope-checklist](scope-checklist/markup.html) | Independent inclusions                           | Repeat the checkbox row with stable option IDs and readable labels. The frame records the whole list, including untouched and empty selections. No behavior script is needed. |
| [behavior-cases](behavior-cases/markup.html)   | Situations and proposed outcomes                 | Repeat the case section. Keep each ID in its contextual comment label. Revise opens the existing comment dialog at that case.                                                 |

Code, diagrams, and charts need no component: the frame renders them as
figures from `data-file`, `data-caption`, and `data-title` (see
[authoring.md](../references/authoring.md)). Notes on the text are frame
behavior.

## Decisions

Use the decision component when the options are short enough to judge from a
title and one line. Put the recommended option first with the tag. Use the
visual decision when each option needs a diagram, code, chart, or prototype to
judge. `data-layout="auto"` shows columns when there are at most three options
and each column would be at least 280px wide, tabs otherwise; `columns` or
`tabs` forces one. In tabs, the pick bar chooses the option on screen, and the
chosen tab carries a tick. The toggle at the top right overrides the layout and
is remembered per decision in the browser.

## Questions

Use a question when the answer is prose rather than a selection. Keep the
question to one sentence and say what the answer decides. Empty answers are
not sent. Answers appear on Feedback as their own items and can be cited as
agreement sources with kind `answer`.

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

HTML-escape that JSON into the markup's `textarea[data-diff-input]`. Put the
file name in `data-file` on the section; it shows in the thin bar with the
layout toggle. The helper preserves both UTF-8 source strings and a unified Git
patch. It requires Git and refuses to overwrite an existing output. Include
`behavior.js` and `styles.css`; the frame loads the pinned Pierre viewer only
when needed.

The viewer is split when the content column is at least 900px wide and
unified below that; the toggle overrides for that diff and is remembered. It
uses the same `github-light` and `github-dark` themes as other Shiki code.
Rendering requires network access. Failures are reported without an offline
renderer. Exact sources and the patch remain in the artifact.

For visual changes, fill the before/proposed HTML slots and explain the changes
in the legend. Apply `added`, `removed`, or `changed` classes to changed content
or Mermaid nodes. Do not set fixed colors in Mermaid `classDef` declarations;
the component supplies theme-aware colors. These annotations express the
author's meaning, not an inferred text diff.
