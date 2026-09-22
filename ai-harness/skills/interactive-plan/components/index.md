# Components

Each directory contains `markup.html`. It also contains `styles.css` and
`behavior.js` when the component needs them. Choose a component for the
structure of the decision, not for its sample content. Copy the markup into a
page and replace its content and IDs. Concatenate the styles and behaviors you use
into the artifact's `css` and `js` files. There is no registration step.
A plan-local component works the same way.

| Directory                                      | Use                                        | Content and interaction                                                                                                                                                   |
| ---------------------------------------------- | ------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [decision](decision/markup.html)               | Two to five text options                   | Radio-style rows. Each row is the `data-value` button with a title, an optional Recommended tag, and one line of consequence.                                             |
| [visual-decision](visual-decision/markup.html) | Options that each need a visual            | Option articles with a header, one line, and a figure. The reviewer can switch between tabs and side-by-side view. Include its styles and behavior.                       |
| [question](question/markup.html)               | An open answer the agent needs             | A card with the Question tag, the question, why it matters, a textarea and an Answer button. Feedback includes the answer under `groups.answers`.                         |
| [comparison](comparison/markup.html)           | Two or three options with matched sections | Repeat the option article. Matching sections align across options. Selection uses the `data-choice` and `data-value` buttons.                                             |
| [before-after](before-after/markup.html)       | A proposed change                          | By default, show either code in the text viewer or diagrams in the visual pair.                                                                                           |
| [scope-checklist](scope-checklist/markup.html) | Independent inclusions                     | Repeat the checkbox row with stable option IDs and readable labels. Start with no boxes checked. The frame includes untouched and empty selections in the submitted list. |
| [behavior-cases](behavior-cases/markup.html)   | Situations and proposed outcomes           | Repeat the case section, with the When and Then labels that show under 700px. Keep each ID in its contextual comment label. Revise opens the comment dialog at that case. |

Set `data-kind` on the root of a component that is not built from those
attributes. Use a singular noun that follows "this". The comment control uses
that value to name the component without component-specific frame code.

Code, diagrams, and charts need no component. The frame renders them as
figures from `data-file`, `data-caption`, and `data-title`, described in
[frame.md](../references/frame.md). A code block also takes `data-lines`
for a focused range, `data-numbers` for the numbers alone, and
`data-notes` for a note on a line, and a formula takes `data-terms` to
name its coloured terms. Notes on the text are frame behavior.

## Decisions

Use the decision component when a title and one line are enough to judge
each option. Put the recommended option first, with the tag. Use the visual
decision when each option needs a diagram, code, a chart, or a prototype. It
shows tabs, one option at a time at full width. The radio header at the top
of the panel is the selection control, and the chosen tab shows a tick. The
reviewer can switch between Tabs and Side by side. The browser remembers that
choice for each decision. Side by side needs
every column to be at least 240px wide and falls back to tabs on a narrow
window. A figure scales to its column in side-by-side view and retains its
natural size in a tab. Give each option one line of consequence that is
specific to it. After recording a choice on Agreed, remove that decision from
the next revision.

## Questions

Use a question when the answer is prose, not a selection. Keep it to one
sentence and say what the answer decides. Empty answers are not sent.
The card has an Answer button. Pressing it shows the answered state with
the text in place and an Edit button. The frame records the text on every
keystroke, whether or not the reviewer presses Answer. Feedback includes
each answer as its own item, and an agreement can cite it with kind `answer`.
After recording the answer on Agreed, remove that question from the next
revision. If the question remains in the revision, ask it again.

## Checklists

Start each checklist with no boxes checked. Mark the items the plan
recommends with the `Recommended` tag. Keep the count line above the rows.
The component updates it. Do not ship a checked box. The agent cannot
distinguish a box the reviewer checked from a box that started checked.

## Matched sections

The comparison aligns matching sections across options. Set
`--comparison-rows` to the number of direct children per option, including
the header and the footer, or use `data-layout="independent"` when the
options have different structures. Columns stack when they no longer fit.
Keep the selection button separate from links, charts, and other
interactive content inside an option. Every option needs the same number
of children for the rows to line up. Include an empty section when an option
has nothing for it. Mark the section `class="comparison-content empty"` and
add one line that says so.

## Before and after

For text or code, generate the input with Git:

```sh
node components/before-after/diff.mjs BEFORE AFTER OUTPUT.json
```

HTML-escape that JSON into the markup's `textarea[data-diff-input]`, and put
the file name in `data-file` on the section, which shows in the bar next to
the layout toggle. The helper writes both UTF-8 sources and a unified Git
patch, requires Git, and refuses to overwrite an existing output. Include
`behavior.js` and `styles.css`. The frame loads the pinned Pierre viewer
only when a page needs it. The viewer is split when the content column is at
least 900px wide and unified below that, and the toggle overrides that per
diff and is remembered. It uses the frame's Shiki themes and needs a network
connection. A failure is reported, and the artifact includes the exact
sources and the patch.

For visual changes, fill the before and proposed slots and explain the
change in the legend. Put the `added`, `removed`, or `changed` class on
changed content or Mermaid nodes. The component supplies colors for both
themes, so do not set fixed colors in Mermaid `classDef` declarations.
These classes state what the author means, not a computed diff.

## Diagram examples

Use the following patterns when you draw a diagram. The frame renders every
diagram at its drawn size and scrolls sideways when it is wider than the
column. Clicking a diagram opens it full size. Inside a side-by-side layout,
a diagram scales to its column.

1. **The form.** Mermaid is the default. Draw a loop as a flowchart when
   the loop is the structure, a sequence diagram when the order of waits is
   the point, and a state diagram for modes. When Mermaid cannot draw the
   idea cleanly, draw the SVG by hand. The hand-written review loop in
   [flow.svg](../references/flow.svg) uses the frame's theme tokens.
2. **Edges into a group.** An edge into a subgraph's first node passes
   through the subgraph's title. Point the edge at the group, or lay the
   flow out left to right.
3. **Long chains.** A ten-hop line can stay at natural size when the order is
   the whole point. Group the same flow when it needs to fit the column, and
   label each group.
4. **Spacing.** The frame sets rank spacing 36, node spacing 28, and a
   title margin of 8. Mermaid's defaults of 50 and 50 cost a screen per
   four nodes, and the frame's values keep titles clear of edges.
5. **Labels.** Put one to three words in a node and the rest in the
   caption. Long labels widen every node in the rank and push the chain
   past the column. Put the sentence in the caption line under the figure.

The fixture under `scripts/fixture/` renders each pair.

```text
2, avoid    flowchart TB · E["Pricing"] --> F · subgraph pay [Payments]
            F["PaymentClient"] --> G["Breaker"] --> H["Gateway"] · end · H --> I["Ledger"]
2, prefer   flowchart TB · E["Pricing"] --> pay · subgraph pay [Payments]
            F["PaymentClient"] --> G["Breaker"] --> H["Gateway"] · end · pay --> I["Ledger"]
3, a line   flowchart LR · Browser --> Edge --> Checkout API --> Cart service --> Pricing
            --> PaymentClient --> Breaker --> Gateway --> Ledger --> Notifier
3, grouped  flowchart TB · subgraph front [Front] direction LR · Browser --> Edge · end
            · subgraph core [Core] direction LR · Checkout API --> Cart service --> Pricing · end
            · subgraph pay [Payments] direction LR · PaymentClient --> Breaker --> Gateway · end
            · front --> core --> pay --> Ledger --> Notifier
5, avoid    flowchart LR · A["Checkout API validates the cart and prices"]
            --> B["PaymentClient with a five-failure breaker"] --> C["Gateway, 8 s timeout"]
5, prefer   flowchart LR · A["Checkout API"] --> B["PaymentClient"] --> C["Gateway"]
            caption: Checkout validates and prices. The client trips after five
            failures. The gateway times out at 8 s.
```
