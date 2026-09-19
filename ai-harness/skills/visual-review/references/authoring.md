# Author a document

A document is a description, one HTML file per page, and optionally a
Mermaid source it opens with. One command turns them into one HTML file.

```sh
node SKILL/scripts/build.mjs WORK/document.json WORK/out/NAME.html
```

Build into a directory of your own. The builder embeds the frame, the
shipped stylesheet, every page, every diagram and change named by a file,
and the opening diagram into one file, and overwrites only a file it wrote.
It does not bundle imports or follow links, so anything else a page needs
must be in the page. The file needs the network when it opens: Mermaid,
ELK, Shiki, the Pierre viewer, KaTeX and ECharts load from
cdn.jsdelivr.net and esm.sh.

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
    { "id": "hub", "title": "The hub's new refusal", "file": "p-hub.html" },
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
| title, subtitle, lede | Text. The subtitle carries the shape of the subject; the lede is one paragraph and appears under the title on the first page.                                                                                            |
| ref                   | The commit every excerpt is read from, through `git show ref:path`. Defaults to `HEAD`. For a pull request, the head of its branch.                                                                                      |
| repository            | Optional path to the repository, relative to the description. Defaults to the directory the build runs in.                                                                                                               |
| opens                 | Optional Mermaid source file. It renders on the first page, under the lede. A document without one opens on its first page's content.                                                                                    |
| pages                 | Ordered records with a unique id, a title, a file of trusted authored HTML, and an optional `depth`. Reading order is list order; `depth: 1` indents the page under the one before it in the rail. No limit on how many. |
| css                   | Optional stylesheet for this document only. Not the normal way to work; see the last section.                                                                                                                            |

Page HTML is trusted authored markup, not Markdown. A page lands in the
frame through `innerHTML`, so a script element in a page never runs; the
one kind that runs is described under Controls.

## Diagrams

```html
<div
  data-diagram
  data-file="round.mmd"
  data-caption="Amber is what the change touched."
></div>
```

```text
flowchart LR
  hub["<span class='title'>the hub</span><span class='path'>session.mjs</span><span class='delta add'>+61</span><span class='delta cut'>−4</span>"]
  card["<span class='title'>the working card</span><span class='path'>steps, ticked</span>"]
  hub --> card
  class hub,card marked
```

Any Mermaid diagram, drawn by ELK on the shipped stylesheet. A flowchart
label may hold spans; the classes the stylesheet paints are `title`,
`path`, `delta add`, `delta cut`, `badge`, and `note`, and `marked` on a
node through `class a,b marked` means the subject touched it. A node whose
id matches a page id opens that page on click, in any diagram. A caption
on `data-caption` frames the figure; a click on any diagram opens it full
size.

Write a diagram in its own `.mmd` file and name it with `data-file`; the build puts it into the page as text. A diagram written inline in the page is also text, so its label markup has to be escaped (`&lt;span class='title'&gt;`); a raw span inline fails the build, because the page would parse it as HTML and Mermaid would never see it. The opening diagram is the same kind of file, named by `opens`.

Sequence and gantt diagrams use Mermaid's own layout and still take the
theme. Keep labels to a few words and put the sentence in the caption; a
long label widens every node in its rank.

## A stylesheet of your own

The shipped stylesheet is what every document uses. A subject that
genuinely needs a piece the stylesheet does not have sets `css` in the
description. Two constraints, both found by breaking them:

1. Rules for the inside of a diagram label are unscoped. Mermaid measures
   a label in a detached element outside the diagram, so a rule scoped to
   the diagram is invisible to the measuring pass and the box comes out too
   small for what it holds.
2. Colouring part of a label needs `!important`, because Mermaid sets a
   colour on the label itself. Padding, radius, font and layout win without
   help.

Every colour in a document stylesheet is a token: `--ground`, `--panel`,
`--line`, `--line-strong`, `--ink`, `--muted`, `--accent`,
`--accent-soft`, `--code`, `--mark`, `--mark-soft`, `--add`, `--add-soft`,
`--cut`, `--cut-soft`. A literal colour fails the build.
