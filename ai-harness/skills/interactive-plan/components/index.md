# Components

Each directory holds `markup.html`, and `styles.css` and `behavior.js`
where the component needs them. Choose a component for the structure of
the decision, not for its sample content. Copy the markup into a page and
replace its content and IDs. Concatenate the styles and behaviors you use
into the artifact's `css` and `js` files. There is no registration step.
A plan-local component works the same way.

| Directory                                      | Use                                        | Content and interaction                                                                                                                                                   |
| ---------------------------------------------- | ------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [decision](decision/markup.html)               | Two to five text options                   | Radio-style rows; each row is the `data-value` button with a title, an optional Recommended tag, and one line of consequence.                                             |
| [visual-decision](visual-decision/markup.html) | Options that each need a visual            | Option articles with a header, one line, and a figure. Tabs, which the reviewer can toggle to side by side. Include its styles and behavior.                              |
| [question](question/markup.html)               | An open answer the agent needs             | A card with the Question tag, the question, why it matters, a textarea and an Answer button. The answer travels with feedback as `groups.answers`.                        |
| [comparison](comparison/markup.html)           | Two or three options with matched sections | Repeat the option article; matching sections align across options. Selection uses the `data-choice` and `data-value` buttons.                                             |
| [before-after](before-after/markup.html)       | A proposed change                          | The text viewer for code, or the visual pair for diagrams; not both by default.                                                                                           |
| [scope-checklist](scope-checklist/markup.html) | Independent inclusions                     | Repeat the checkbox row with stable option IDs and readable labels. Nothing starts checked. The frame records the whole list, including untouched and empty selections.   |
| [behavior-cases](behavior-cases/markup.html)   | Situations and proposed outcomes           | Repeat the case section, with the When and Then labels that show under 700px. Keep each ID in its contextual comment label; Revise opens the comment dialog at that case. |

A component that is not built from those attributes sets `data-kind` on its
root, a singular noun that follows "this", so the comment control names it
without the frame knowing the component.

Code, diagrams, and charts need no component. The frame renders them as
figures from `data-file`, `data-caption`, and `data-title`; see
[frame.md](../references/frame.md). A code block also takes `data-lines`
for a focused range, `data-numbers` for the numbers alone, and
`data-notes` for a note on a line, and a formula takes `data-terms` to
name its coloured terms. Notes on the text are frame behavior.

## Decisions

Use the decision component when a title and one line are enough to judge
each option. Put the recommended option first, with the tag. Use the visual
decision when each option needs a diagram, code, a chart, or a prototype.
It shows tabs, one option at a time at full width, with the option's radio
header at the top of the panel as the pick, and the chosen tab carries a
tick. The toggle at the top right, Tabs · Side by side, is the reviewer's
own choice and is remembered per decision in the browser; side by side
needs every column to be at least 240px wide and falls back to tabs on a
narrow window. A figure inside an option shrinks to its column side by side
and keeps its size in a tab. Give each option one line of
consequence that is specific to it. Remove a decision in the revision that
records its choice on Agreed.

## Questions

Use a question when the answer is prose, not a selection. Keep it to one
sentence and say what the answer decides. Empty answers are not sent.
The card carries an Answer button: pressing it shows the answered state
with the text in place and an Edit button, and the frame records the text
on every keystroke either way, so an answer that was never marked done
still travels with the round.
Answers appear on Feedback as their own items and can be cited as
agreement sources with kind `answer`. Remove the question in the revision
that records the answer on Agreed; a question that stays gets answered
again.

## Checklists

A checklist arrives with nothing checked. Mark the items the plan
recommends with the `Recommended` tag and keep the count line above the
rows; the behavior updates it. Do not ship a checked box: a box the
reviewer never pressed is what made agreement and silence arrive at the
agent as the same thing.

## Matched sections

The comparison aligns matching sections across options. Set
`--comparison-rows` to the number of direct children per option, including
the header and the footer, or use `data-layout="independent"` when the
options have different structures. Columns stack when they no longer fit.
Keep the selection button separate from links, charts, and other
interactive content inside an option. Every option needs the same number
of children for the rows to line up; an option that has nothing to say in
a section keeps the section and marks it `class="comparison-content empty"`
with one line saying so.

## Before and after

For text or code, generate the input with Git:

```sh
node components/before-after/diff.mjs BEFORE AFTER OUTPUT.json
```

HTML-escape that JSON into the markup's `textarea[data-diff-input]`, and
put the file name in `data-file` on the section; it shows in the bar next
to the layout toggle. The helper writes both UTF-8 sources and a unified
Git patch, requires Git, and refuses to overwrite an existing output.
Include `behavior.js` and `styles.css`; the frame loads the pinned Pierre
viewer only when a page needs it. The viewer is split when the content
column is at least 900px wide and unified below that; the toggle overrides
that per diff and is remembered. It uses the frame's Shiki themes and needs
a network connection. A failure is reported, and the exact sources and the
patch stay in the artifact.

For visual changes, fill the before and proposed slots and explain the
change in the legend. Put the `added`, `removed`, or `changed` class on
changed content or Mermaid nodes. The component supplies colors for both
themes, so do not set fixed colors in Mermaid `classDef` declarations.
These classes state what the author means, not a computed diff.

## Diagrams

The pairs below show common mistakes and their fixes. The frame renders
every diagram at its drawn size and scrolls sideways when it is wider than
the column; a click opens it full size. Inside a side-by-side layout, a
diagram shrinks to its column instead.

1. **The form.** Mermaid is the default. Draw a loop as a flowchart when
   the loop is the structure, a sequence diagram when the order of waits is
   the point, and a state diagram for modes. When Mermaid cannot draw the
   idea cleanly, draw the SVG by hand; the skill's own review loop
   ([flow.svg](../references/flow.svg)) is one, and it follows the frame's
   theme through the tokens.
2. **Edges into a group.** An edge into a subgraph's first node passes
   through the subgraph's title. Point the edge at the group, or lay the
   flow out left to right.
3. **Long chains.** Ten hops in a line read at natural size by scrolling,
   which is fine when the order is the whole point. Grouped, the same flow
   fits the column and names its parts.
4. **Spacing.** The frame sets rank spacing 36, node spacing 28, and a
   title margin of 8. Mermaid's defaults of 50 and 50 cost a screen per
   four nodes; the frame's values keep titles clear of edges.
5. **Labels.** Put one to three words in a node and the rest in the
   caption. Long labels widen every node in the rank and push the chain
   past the column. The caption line under the figure carries the sentence.

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
            caption: Checkout validates and prices; the client trips after five failures;
            the gateway times out at 8 s.
```
