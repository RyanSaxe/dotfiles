# Author a document

A document is a description file, one HTML file per page, and optionally a
Mermaid file for the opening diagram. One command turns them into one HTML
file.

```sh
node SKILL/scripts/build.mjs WORK/document.json WORK/out/NAME.html
```

Build into a directory of your own. The builder puts the frame, the
stylesheet, every page, every diagram and change named by a file, and the
opening diagram into one file. It overwrites only a file it built. It does
not bundle imports or follow links, so anything else a page needs must be
in the page. The file needs the network when it opens: Mermaid, ELK, Shiki,
the Pierre viewer, KaTeX and ECharts load from cdn.jsdelivr.net and esm.sh.

## The description

```json
{
  "documentId": "interactive-plan-142",
  "title": "A progress card, from the terminal to the page",
  "subtitle": "8 commits · 23 files · +1,790 −215",
  "lede": "One paragraph under the title, on the first page.",
  "ref": "a286050",
  "opens": "opening.mmd",
  "pages": [
    { "id": "hub", "title": "The hub's new check", "file": "p-hub.html" },
    {
      "id": "draft",
      "title": "What counts as unsent",
      "file": "p-draft.html",
      "depth": 1
    }
  ]
}
```

| Field                 | Contract                                                                                                                                                                                                                 |
| --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| documentId            | Letters, digits, underscores, hyphens.                                                                                                                                                                                   |
| title, subtitle, lede | Text. The subtitle gives the size or shape of the subject. The lede is one paragraph and appears under the title on the first page.                                                                                      |
| ref                   | The commit every excerpt is read from, through `git show ref:path`. Defaults to `HEAD`. For a pull request, use the head of its branch.                                                                                  |
| repository            | Optional path to the repository, relative to the description. Defaults to the directory the build runs in.                                                                                                               |
| opens                 | Optional Mermaid file. It renders on the first page, under the lede. A document without one opens on its first page's content.                                                                                           |
| opensCaption          | Optional caption under the opening diagram.                                                                                                                                                                              |
| pages                 | Ordered records with a unique id, a title, a file of trusted authored HTML, and an optional `depth`. Reading order is list order; `depth: 1` indents the page under the one before it in the rail. No limit on how many. |
| css                   | Optional stylesheet for this document only. See the last section.                                                                                                                                                        |

Page HTML is trusted markup written by the agent, not Markdown. A page is
inserted into the frame through `innerHTML`, so a script element in a page
never runs. The one kind of script that runs is described under Controls.

## Diagrams

```html
<div
  data-diagram
  data-file="round.mmd"
  data-caption="Amber marks the parts the change touched."
></div>
```

```text
flowchart LR
  hub["<span class='title'>the hub</span><span class='path'>session.mjs</span><span class='delta add'>+61</span><span class='delta cut'>−4</span>"]
  card["<span class='title'>the working card</span><span class='path'>steps, ticked</span>"]
  hub --> card
  class hub,card marked
```

A page can hold any Mermaid diagram. ELK lays it out and the shipped
stylesheet colours it. A flowchart label can contain spans with these
classes: `title`, `path`, `delta add`, `delta cut`, `badge`, `note`. The
line `class a,b marked` colours nodes a and b amber, which means the
subject touched them. In any diagram, clicking a node whose id matches a
page id opens that page. `data-caption` puts a caption under the figure.
Clicking a diagram opens it at its drawn size in a lightbox; a diagram
wider than the column is scaled down to fit until then.

Write a diagram in its own `.mmd` file and name it with `data-file`. The
build copies the file into the page as escaped text. A diagram written
directly in the page is parsed as HTML before Mermaid sees it, so its label
markup would have to be escaped by hand (`&lt;span class='title'&gt;`), and
the build fails on a raw span inside an inline diagram. The opening diagram
is the same kind of file, named by `opens`.

Sequence and gantt diagrams use Mermaid's own layout and take the theme.
Keep their labels to a few words and put the sentence in the caption; a
long label widens every node in its rank.

## Code

```html
<figure
  class="excerpt"
  data-file="scripts/session.mjs"
  data-lines="559-564"
  data-language="javascript"
>
  <ol class="notes">
    <li data-line="564" data-span="560-564">
      <b>Why 409</b>
      The request is well formed, so this is not a 400. The state is wrong.
    </li>
  </ol>
</figure>
```

The build reads the lines from the repository at `ref`; do not type them
into the page. The build fails if the file does not exist at that commit
or the range runs past its end. `data-line` is the line a note attaches
to, which is the last line of the code it describes. `data-span` is an
optional range of lines to tint. Both must fall inside `data-lines`, or the
build fails. Notes appear after their line, at full width. The header shows
the file and the range. Shiki highlights the lines in the reader's theme,
so `data-language` must be a Shiki language id: `javascript`, `python`,
`sh`, `markdown`, `json`.

For a block of code that is not from the repository, put the source in the
page as HTML-escaped text:

```text
<div data-language="sh" data-file="what was run">
git show a286050:scripts/session.mjs &gt; before.mjs
</div>
```

## Diffs

```sh
git show BASE:assets/draft.mjs > before.mjs
git show HEAD:assets/draft.mjs > after.mjs
node SKILL/components/diff/diff.mjs before.mjs after.mjs change.json
```

```html
<figure
  class="change"
  data-file="assets/draft.mjs"
  data-change="change.json"
></figure>
```

The helper takes the two versions of the file and writes a JSON file
holding both and a git patch. Name that file with `data-change` and the
build puts it into the figure. `data-file` is the path the header shows.
The JSON can also be written into the page by hand: HTML-escape it into
`<textarea data-diff-input hidden>` and put `<div class="change-view"></div>`
next to it. Either way, the build fails on a change whose input is not
JSON with `before`, `after` and `patch`. The frame renders the change in
the Pierre viewer, with a side-by-side and unified toggle in the header,
in the document's colours. Every change a document shows goes through the
viewer.

## Charts

```html
<div
  data-chart
  data-title="Latency, before and after"
  data-caption="p50 over a week."
>
  { "xAxis": { "type": "category", "data": ["Mon", "Tue"] }, "yAxis": { "type":
  "value" }, "series": [{ "type": "line", "data": [12, 9] }] }
</div>
```

The content is an ECharts option object as JSON. The frame sets the
background, the text colour and the axis colours from the tokens, and
gives the series the tokens in this order: accent, amber, green, red,
grey.

## Mathematics

```text
<p>The loss is scaled by <span data-math="inline">\alpha</span>.</p>
<div data-math="display">\mathrm{FL}(p_t) = -\,\alpha\,(1-p_t)^{\htmlData{lines=17 19}{\gamma}}\,\log(p_t)</div>
```

KaTeX renders the content, inline or display. To make a symbol point at
its code, wrap it in `\htmlData{lines=17 19}{…}` with the line numbers
separated by spaces. Pressing the symbol highlights those lines in every
excerpt on the page. Most equations need no such link.

## Controls

```html
<figure class="figure" data-figure="focal">
  <div data-chart></div>
  <div class="controls">
    <label
      >focusing
      <input
        type="range"
        data-control="gamma"
        min="0"
        max="5"
        step="0.1"
        value="2" />
      <output></output
    ></label>
  </div>
  <script type="text/plain" data-script>
    const xs = Array.from({ length: 99 }, (_, i) => (i + 1) / 100);
    draw.chart({
      xAxis: { type: "category", data: xs.map((x) => x.toFixed(2)) },
      yAxis: { type: "value" },
      series: [{ type: "line", showSymbol: false,
        data: xs.map((p) => -((1 - p) ** controls.gamma) * Math.log(p)) }],
    });
  </script>
</figure>
```

A control is an input with `data-control="name"` inside the figure. When
a control changes, the figure's script runs again with three arguments:
`controls`, an object with every control's value by name; `figure`, the
figure element; and `draw`, which has `draw.chart(options)` for a
`[data-chart]` inside the figure and `draw.text(selector, string)` for any
other element. An `output` element next to an input shows the input's
value.

The script receives those three arguments and nothing else. It may not use
`fetch`, `XMLHttpRequest`, `localStorage`, `sessionStorage`, `indexedDB`,
`document` or `window`; the build fails on a script that names any of
them. Most figures have no controls.

## A document's own stylesheet

Every document uses the shipped stylesheet. A document that needs a rule
the stylesheet does not have sets `css` in the description. Two things
about the stylesheet affect such rules:

1. Rules for the inside of a diagram label are not scoped to the diagram.
   Mermaid measures a label in a detached element outside the diagram, so
   a rule scoped to the diagram does not apply during measuring, and the
   node comes out too small for its label.
2. Colouring part of a label needs `!important`, because Mermaid sets a
   colour on the label itself. Padding, radius, font and layout do not.

Every colour in a document stylesheet must be a token: `--ground`,
`--panel`, `--line`, `--line-strong`, `--ink`, `--muted`, `--accent`,
`--accent-soft`, `--code`, `--mark`, `--mark-soft`, `--add`, `--add-soft`,
`--cut`, `--cut-soft`. The build fails on a literal colour.
