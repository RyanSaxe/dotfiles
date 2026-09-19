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
