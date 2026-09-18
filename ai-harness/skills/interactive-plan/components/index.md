# Components

Each directory holds `markup.html`, `styles.css`, and `behavior.js` where one
is needed. Choose a component for the structure of the decision, not its
sample content. Copy the markup into a page and replace its content slots and
IDs; concatenate the styles and behaviors you use into the artifact's `css`
and `js` files. There is no registration step, and a plan-local component
follows the same workflow.

| Directory                                      | Use                                        | Content and interaction                                                                                                                           |
| ---------------------------------------------- | ------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| [decision](decision/markup.html)               | Two to five text options                   | Radio-style rows; each row is the `data-value` button with a title, an optional Recommended tag, and one line of consequence.                     |
| [visual-decision](visual-decision/markup.html) | Options that each need a visual            | Option articles with a header, one line, and a figure. Columns or tabs by width and option count, with a toggle. Include its styles and behavior. |
| [question](question/markup.html)               | An open answer the agent needs             | A card with a stripe, the question, why it matters, and a textarea. The answer travels with feedback as `groups.answers`.                         |
| [comparison](comparison/markup.html)           | Two or three options with matched sections | Repeat the option article; matching sections align across options. Selection uses the `data-choice` and `data-value` buttons.                     |
| [before-after](before-after/markup.html)       | A proposed change                          | The text viewer for code, or the visual pair for diagrams; not both by default.                                                                   |
| [scope-checklist](scope-checklist/markup.html) | Independent inclusions                     | Repeat the checkbox row with stable option IDs and readable labels. The frame records the whole list, including untouched and empty selections.   |
| [behavior-cases](behavior-cases/markup.html)   | Situations and proposed outcomes           | Repeat the case section. Keep each ID in its contextual comment label; Revise opens the comment dialog at that case.                              |

Code, diagrams, and charts need no component: the frame renders them as
figures from `data-file`, `data-caption`, and `data-title` (see
[authoring.md](../references/authoring.md)). Notes on the text are frame
behavior.

## Decisions

Use the decision when a title and one line are enough to judge each option;
put the recommended option first with the tag. Use the visual decision when
each option needs a diagram, code, chart, or prototype. Its
`data-layout="auto"` shows columns when there are at most three options and
each column would be at least 280px wide, and tabs otherwise; `columns` or
`tabs` forces one. In tabs, the pick bar chooses the option on screen and the
chosen tab carries a tick; the toggle at the top right overrides the layout
and is remembered per decision in the browser. Give each option one line of
consequence, concrete and specific to it. Remove a decision in the revision
that records its choice on Agreed.

## Questions

Use a question when the answer is prose rather than a selection. Keep it to
one sentence and say what the answer decides. Empty answers are not sent;
answers appear on Feedback as their own items and can be cited as agreement
sources with kind `answer`. Remove the question in the revision that records
the answer on Agreed; a question that stays gets answered again.

## Matched sections

The comparison aligns matching sections across options. Set
`--comparison-rows` to the number of direct children per option, including
header and footer, or use `data-layout="independent"` when the options have
different structures. Columns stack when they no longer fit. Keep selection
separate from links, charts, and other interactive content inside an option.

## Before and after

For text or code, generate the input with Git:

```sh
node components/before-after/diff.mjs BEFORE AFTER OUTPUT.json
```

HTML-escape that JSON into the markup's `textarea[data-diff-input]`, and put
the file name in `data-file` on the section, where it shows in the bar with
the layout toggle. The helper preserves both UTF-8 sources and a unified Git
patch, requires Git, and refuses to overwrite an existing output. Include
`behavior.js` and `styles.css`; the frame loads the pinned Pierre viewer only
when needed. The viewer is split when the content column is at least 900px
wide and unified below that; the toggle overrides per diff and is remembered.
It uses the frame's Shiki themes and needs a connection; failures are reported
and the exact sources and patch remain in the artifact.

For visual changes, fill the before and proposed slots and explain the change
in the legend. Apply `added`, `removed`, or `changed` classes to changed
content or Mermaid nodes; the component supplies theme-aware colors, so do not
set fixed colors in Mermaid `classDef` declarations. These annotations express
the author's meaning, not an inferred diff.
