# Components

A component is a directory the builder bundles into every revision. Copy
its `markup.html` into a page and replace the content and IDs. Its styles
and behavior are already in the frame, so they do not belong in the page's
`css` or `js`. Component CSS outranks page CSS, so do not restyle a
component. A component is as wide as the reading column.

| Directory                                        | Use                                        | Content and interaction                                                                                                                                                                    |
| ------------------------------------------------ | ------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| [decision](decision/markup.html)                 | Options that differ in policy or wording   | Radio-style rows. Each row is the `data-value` button with a title, an optional Recommended tag, and one line of consequence.                                                              |
| [visual-decision](visual-decision/markup.html)   | Options that differ in something visible   | Option articles with a header, one line, and a figure. The reviewer can switch between tabs and side-by-side view.                                                                         |
| [question](question/markup.html)                 | An open answer the agent needs             | The question, why it matters, a textarea and an Answer button. Feedback includes the answer under `groups.answers`.                                                                        |
| [drawing-question](drawing-question/markup.html) | A spatial answer the reviewer should draw  | A full-screen drawing editor. The answer includes an editable Excalidraw scene and a PNG preview. Needs a live hub and a network connection.                                               |
| [comparison](comparison/markup.html)             | Two or three options with matched sections | Repeat the option article. Matching sections align across options. Selection uses the `data-choice` and `data-value` buttons.                                                              |
| [before-after](before-after/markup.html)         | A proposed change                          | A Git diff for text or code, or a before and proposed pair for diagrams and other visuals.                                                                                                 |
| [scope-checklist](scope-checklist/markup.html)   | Independent inclusions                     | Repeat the checkbox row with stable option IDs and readable labels.                                                                                                                        |
| [behavior-cases](behavior-cases/markup.html)     | Situations and proposed outcomes           | Repeat the case section with its When and Then labels. Keep each ID in its contextual comment label.                                                                                       |
| [code](code/markup.html)                         | Source code                                | `data-language` with the source as escaped text.                                                                                                                                           |
| [formula](formula/markup.html)                   | Inline or display math                     | `data-math` set to inline or display. `data-terms` names the coloured terms under the formula.                                                                                             |
| [diagram](diagram/markup.html)                   | A diagram                                  | `data-diagram` with Mermaid source as text. Nodes whose IDs match page IDs open those pages, and a click opens the diagram full size.                                                      |
| [chart](chart/markup.html)                       | A chart or a mathematical demonstration    | `data-chart` with an ECharts option object as JSON text. The frame applies the theme palette.                                                                                              |
| [prototype](prototype/markup.html)               | An approved or proposed interaction        | `data-prototype` naming an entry in the page's `prototypes`. The frame supplies the sandboxed frame, the Source fold and Open full size. See [prototypes.md](../references/prototypes.md). |

When a page needs a shape no component has, build it in the page's own `css`
and `js`. When the user asks to keep it for later plans, follow
[README.md](README.md) to move it into
`$XDG_CONFIG_HOME/interactive-plan/components/<name>/` and say the path.
Never offer this.

## Code and figures

`data-language` is the language's name in Shiki, the highlighter: `ts`,
`python`, `shell`, `json`, or `text` for plain text. The build refuses a
name Shiki does not know and suggests the nearest one.

`data-file` on a code block adds a header with the file name, the language
and a Copy button. `data-caption` on code, a diagram or a chart adds a
caption line, and `data-title` on a chart adds a header.

| Attribute    | On                | What it does                                                                                                                       |
| ------------ | ----------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| data-lines   | `[data-language]` | `"3-4"` or `"7"`. Numbers the lines, lights the range, and dims the rest until the pointer or the keyboard is on the block.        |
| data-numbers | `[data-language]` | Takes no value. Numbers the lines and dims nothing.                                                                                |
| data-notes   | `[data-language]` | `[{"line": 3, "text": "…"}]`. A speech bubble in the gutter of each named line, opening the note in a popover. Needs no range.     |
| data-terms   | `[data-math]`     | `[{"symbol": "t", "meaning": "…", "value": "8 s"}]`. Names the formula's coloured terms under it, in the order the colours appear. |

Use `data-lines` only when the selected range is the subject of the review,
and `data-notes` only when the exact line needs an explanation. Leave both
off routine code examples.

A code block's source is HTML text, so write `&lt;` for `<` and `&amp;` for
`&`. Nothing checks this: unescaped, `&lt;T&gt;` becomes a tag and the rest
of the line disappears. Write a multi-line block as a `<pre>`, which keeps
its line breaks. Use the code component for source code, never a bare block.

A formula term takes its colour from a literal in the source, because KaTeX
refuses `\htmlClass`: write `\textcolor{#1d4ed8}`, `\textcolor{#a16207}`,
`\textcolor{#047857}` or `\textcolor{#9333ea}`, and the frame swaps the
literal for a class that follows the theme. Escape backslashes again when
math is inside a JSON string.

## Decisions

Use the visual decision whenever the options differ in something the
reviewer could see: a layout, a flow, a structure, code, a chart or a
prototype. Put that figure in each option. Use the plain decision only when a
title and one line are enough to judge each option. Put the recommended
option first, with the tag.
Side by side needs every column to be at least 240px wide, and a figure
scales to its column there and keeps its natural size in a tab. Give each
option one line of consequence that is specific to it. After recording a
choice on Agreed, remove that decision from the next revision.

## Questions and checklists

Use a question when the answer is prose, not a selection. Keep it to one
sentence and say what the answer decides. Use a drawing question when the
reviewer needs to sketch a boundary, flow or layout. After recording an
answer on Agreed, remove the question from the next revision. A question
left in the revision asks again.

Start each checklist with no boxes checked, because the agent cannot tell a
box the reviewer checked from one that started checked. Mark the items the
plan recommends with the `Recommended` tag. Keep the count line above the
rows. The component updates it.

## Matched sections

The comparison aligns matching sections across options. Set
`--comparison-rows` to the number of direct children per option, including
the header and the footer, or use `data-layout="independent"` when the
options have different structures. Every option needs the same number of
children for the rows to line up, so include an empty section when an option
has nothing for it: `class="comparison-content empty"` with one line that
says so. Keep the selection button separate from links, charts and other
interactive content inside an option.

## Before and after

For text or code, generate the input with Git:

```sh
node components/before-after/diff.mjs BEFORE AFTER OUTPUT.json
```

Put that JSON in the markup's `textarea[data-diff-input]` with each `&`
written as `&amp;` and each `<` as `&lt;`, and put the file name in
`data-file` on the section. The patch names the file by AFTER's base name, so
give the proposed copy the file's real name, or a name that says what it is. The helper requires Git and refuses to
overwrite an existing output.

For visual changes, fill the before and proposed slots and explain the
change in the legend. Put the `added`, `removed` or `changed` class on
changed content or Mermaid nodes. The component colors them for both themes,
so do not set fixed colors in Mermaid `classDef` declarations.

## Diagrams

Mermaid is the default. Draw a loop as a flowchart when the loop is the
structure, a sequence diagram when the order of waits is the point, and a
state diagram for modes. When Mermaid cannot draw the idea cleanly, draw the
SVG by hand with the frame's tokens, as [flow.svg](../references/flow.svg)
does. A diagram renders at its drawn size and scrolls sideways when it is
wider than the column.

1. **Edges into a group.** An edge into a subgraph's first node passes
   through the subgraph's title. Point the edge at the group, or lay the
   flow out left to right.
2. **Long chains.** A ten-hop line can stay at natural size when the order
   is the whole point. Group the same flow when it needs to fit the column,
   and label each group.
3. **Labels.** Put one to three words in a node and the sentence in the
   caption. Long labels widen every node in the rank and push the chain past
   the column.

```text
1, avoid    flowchart TB · E["Pricing"] --> F · subgraph pay [Payments]
            F["PaymentClient"] --> G["Breaker"] --> H["Gateway"] · end · H --> I["Ledger"]
1, prefer   flowchart TB · E["Pricing"] --> pay · subgraph pay [Payments]
            F["PaymentClient"] --> G["Breaker"] --> H["Gateway"] · end · pay --> I["Ledger"]
2, grouped  flowchart TB · subgraph front [Front] direction LR · Browser --> Edge · end
            · subgraph core [Core] direction LR · Checkout API --> Cart service --> Pricing · end
            · subgraph pay [Payments] direction LR · PaymentClient --> Breaker --> Gateway · end
            · front --> core --> pay --> Ledger --> Notifier
3, avoid    flowchart LR · A["Checkout API validates the cart and prices"]
            --> B["PaymentClient with a five-failure breaker"] --> C["Gateway, 8 s timeout"]
3, prefer   flowchart LR · A["Checkout API"] --> B["PaymentClient"] --> C["Gateway"]
            caption: Checkout validates and prices. The client trips after five
            failures. The gateway times out at 8 s.
```
