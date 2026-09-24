# Components

A component is a directory the builder reads. It holds `markup.html`, and
`styles.css` and `behavior.mjs` when the component needs them. The builder
includes these in the frame pinned by the Agreed page, so an author copies
the markup into a page and replaces its content and IDs. The component's
styles and behavior do not belong in the page's `css` or `js`.

Choose a component for the structure of the decision, not for its sample
content.

| Directory                                        | Use                                        | Content and interaction                                                                                                                                                                      |
| ------------------------------------------------ | ------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [decision](decision/markup.html)                 | Two to five text options                   | Radio-style rows. Each row is the `data-value` button with a title, an optional Recommended tag, and one line of consequence.                                                                |
| [visual-decision](visual-decision/markup.html)   | Options that each need a visual            | Option articles with a header, one line, and a figure. The reviewer can switch between tabs and side-by-side view.                                                                           |
| [question](question/markup.html)                 | An open answer the agent needs             | A card with the Question tag, the question, why it matters, a textarea and an Answer button. Feedback includes the answer under `groups.answers`.                                            |
| [drawing-question](drawing-question/markup.html) | A spatial answer the reviewer should draw  | Opens a full-screen drawing editor. Save records an editable Excalidraw scene and PNG preview; Cancel preserves the prior answer. Requires a live hub and network access to load the editor. |
| [comparison](comparison/markup.html)             | Two or three options with matched sections | Repeat the option article. Matching sections align across options. Selection uses the `data-choice` and `data-value` buttons.                                                                |
| [before-after](before-after/markup.html)         | A proposed change                          | By default, show either code in the text viewer or diagrams in the visual pair.                                                                                                              |
| [scope-checklist](scope-checklist/markup.html)   | Independent inclusions                     | Repeat the checkbox row with stable option IDs and readable labels. Start with no boxes checked. The frame includes untouched and empty selections in the submitted list.                    |
| [behavior-cases](behavior-cases/markup.html)     | Situations and proposed outcomes           | Repeat the case section, with the When and Then labels that show under 700px. Keep each ID in its contextual comment label. Revise opens the comment dialog at that case.                    |
| [code](code/markup.html)                         | Source code                                | `data-language` with the source as escaped text. `data-lines`, `data-numbers` and `data-notes` add a focused range, numbers and a note on a line.                                            |
| [formula](formula/markup.html)                   | Inline or display math                     | `data-math` set to inline or display. `data-terms` names the coloured terms under the formula.                                                                                               |
| [diagram](diagram/markup.html)                   | A diagram                                  | `data-diagram` with Mermaid source as text. ELK lays it out, nodes whose IDs match page IDs open those pages, and a click opens the diagram full size.                                       |
| [chart](chart/markup.html)                       | A chart or a mathematical demonstration    | `data-chart` with an ECharts option object as JSON text. The frame renders charts as SVG and applies the theme palette.                                                                      |
| [prototype](prototype/markup.html)               | An approved prototype                      | `data-prototype` naming an entry in the owning page source. The frame supplies the sandboxed frame, the Source fold and Open full size.                                                      |

The last five carry no interaction of their own: they are the figures a page
puts inside another component or on its own. They are components in the same
sense as the rest, which is why they live here.

## Writing one

A component registers itself. `behavior.mjs` calls `planUI.define`, and the
frame runs every registration over each page as it renders:

```js
planUI.define("scope-checklist", {
  match: ".scope-list[data-multiselect]",
  setup(list, { page, planUI }) {
    // Runs once per matching element, on every page render.
  },
});
```

`match` is a CSS selector. `setup` runs for each element the selector finds,
guarded so it never runs twice on the same element, and a failure prints in
its place and leaves the rest of the page rendered. A `setup` that returns a
promise is awaited before the frame restores the scroll position.

A page renders by replacing `#page-content`, so `setup` runs again on every
visit. Hold nothing between renders. A viewing preference the reader chose,
such as a layout, belongs in `planUI.prefs`, keyed by `page.id` and the
element's own ID so two of the same component on a page stay separate.

`styles.css` needs no wrapper. The builder writes it into a cascade layer
that beats page CSS, so a component's chrome is not restyled by
accident. It also beats `frame.css`, so a component sets its own type and
spacing without fighting a frame selector. Use the design tokens in
[frame.md](../references/frame.md).

The frame supplies the shared parts a component uses directly: `figure()`
for a figure's header, actions and caption, `copyButton()`, `failed()` for a
renderer error in place, `script()` with the pinned CDN locations in
`libraries`, `color()` for a token's current value, and `readData()` for a
JSON array in a data attribute. Everything a plan can reach is on `planUI`,
and a component calls another component through it: the prototype renders
its source fold with `planUI.enhance`, and the chart calls `planUI.chart`.

A directory may hold files the browser never sees. `before-after/diff.mjs`
is a command the agent runs; the builder reads `markup.html`, `styles.css`
and `behavior.mjs` and nothing else.

## Components of your own

A page that needs a shape no component has builds it in its own `css` and
`js`. Those fields refer to files in the page source.

To keep one for later, ask. The agent then writes
`$XDG_CONFIG_HOME/interactive-plan/components/<name>/` with `markup.html`,
`styles.css` and `behavior.mjs`, moves the code out of the page's files, and
says the path. `~/.config` is the fallback when `XDG_CONFIG_HOME` is unset.
Every later plan gets it with nothing copied, and a skill update cannot
touch it, because the skill is installed and updated as a unit.

A name there replaces the skill's component of the same name, which is how a
shipped component gets changed without forking the skill.

The agent never offers this. A session that invents a one-off writes nothing
outside the artifact unless the user asks for it.

## Figures

`data-file` on a code block adds a header with the file name, the language
and a Copy button. `data-caption` on code, a diagram or a chart adds a
caption line, and `data-title` on a chart adds a header. Each of those puts
the block in a figure.

| Attribute    | On                | What it does                                                                                                                       |
| ------------ | ----------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| data-lines   | `[data-language]` | `"3-4"` or `"7"`. Numbers the lines, lights the range, and dims the rest until the pointer or the keyboard is on the block.        |
| data-numbers | `[data-language]` | Takes no value. Numbers the lines and dims nothing.                                                                                |
| data-notes   | `[data-language]` | `[{"line": 3, "text": "…"}]`. A speech bubble in the gutter of each named line, opening the note in a popover. Needs no range.     |
| data-terms   | `[data-math]`     | `[{"symbol": "t", "meaning": "…", "value": "8 s"}]`. Names the formula's coloured terms under it, in the order the colours appear. |

A term takes its colour from a literal in the source, because KaTeX runs
with no `trust` option and refuses `\htmlClass`: write
`\textcolor{#1d4ed8}`, `\textcolor{#a16207}`, `\textcolor{#047857}` or
`\textcolor{#9333ea}` and the frame swaps the literal for the class that
follows the theme. Those four are a content palette, separate from
`--accent`, `--ok`, `--attention` and `--danger`, which indicate state in the
chrome. A block that scrolls sideways fades its right edge while content
remains off-screen. Language grammars load on demand; an unsupported
language shows the source and reports the failure. Escape backslashes again
when math is stored inside a JSON string.

A page is HTML, so a code block's source is escaped: write `&lt;` for `<`
and `&amp;` for `&`. Nothing checks this. Unescaped, the browser reads
`&lt;T&gt;` as a tag and drops the rest of the line, and the build reports
nothing. A `<pre>` keeps its lines as written and a `<div>` does not, so
write a multi-line block as a `<pre>`; both render the same.

Use the code component for source code, never a bare block, and
[before-after](before-after/markup.html) for a proposed change. Native SVG
is still right when it presents the content more clearly.

## Slots

A component that holds authored content gives it a slot, and the frame
supplies the space around it. Put what you like in one: a code block, a
table, a diagram, a paragraph. The slot zeroes the outer margin of its first
and last child, so a `<pre>`, a `<div>`, a figure and a table all sit the
same distance from the slot's edges, above and below.

| Component       | Slot                      |
| --------------- | ------------------------- |
| visual-decision | `.visual-option > figure` |
| comparison      | `.comparison-content`     |
| before-after    | `.change-content`         |
| behavior-cases  | `.behavior-case > div`    |

The `slots` page of the fixture under `scripts/fixture/` holds every slot
against every kind of element. Open it after changing any of this.

Set `data-kind` on the root of a component that is not built from those
attributes. Use a singular noun that follows "this". The comment control uses
that value to name the component without component-specific frame code.

Notes on the text are frame behavior.

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
the text in place and an Edit button. Typing keeps a draft in the box;
pressing Answer records it. Editing an answer keeps the recorded text until
Answer is pressed again. Feedback includes each answer as its own item, and
an agreement can cite it with kind `answer`.
After recording the answer on Agreed, remove that question from the next
revision. If the question remains in the revision, ask it again.

Use a drawing question when the reviewer needs to sketch a boundary, flow, or
layout rather than write prose. The editor loads only when opened. Saved
drawings remain editable; the submitted answer includes session-owned scene
and preview paths for the agent to inspect. A drawing cannot be added to an
offline artifact.

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
patch, requires Git, and refuses to overwrite an existing output. The frame loads the pinned Pierre viewer
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
