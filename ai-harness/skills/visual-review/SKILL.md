---
name: visual-review
description: Explain a subject in a repository as one self-contained HTML document a reader opens in a browser, built around diagrams, real code and diffs, with pages for a complicated subject. Use only when the user explicitly invokes visual-review by name, never for ordinary questions about code.
---

# Visual review

visual-review explains a subject in a repository as one HTML file. The
subject can be a pull request, a subsystem, a repository the reader has
never opened, or a model with mathematics in it. The agent writes the
document, builds it, opens it, and rebuilds it when the reader asks for
changes. It is not a code review, and it posts nothing anywhere.

## The loop

1. Read the repository until you can explain the subject to someone who
   has never opened it. Decide what the subject needs: which parts, which
   diagrams, which lines of code, which changes, and whether an equation
   or a chart says something better than a paragraph would.
2. Write `document.json` and one HTML file per page in a working
   directory outside the repository.
   [authoring.md](references/authoring.md) describes the description
   format and every kind of figure; read it before writing.
   [writing.md](references/writing.md) describes the prose.
   [components](components/index.md) holds one sample file per figure to
   copy from.
3. Build the file and open it. `SKILL` is this skill's directory and
   `WORK` is the working directory. Run the build from inside the
   repository, or set `repository` in the description, because the build
   reads quoted code from the repository through git at the commit named
   by `ref`.

   ```sh
   node SKILL/scripts/build.mjs WORK/document.json WORK/out/NAME.html
   open WORK/out/NAME.html
   ```

   The build fails when a document quotes lines the file does not have,
   puts a note outside its excerpt, marks a node that does not exist, uses
   a label class the stylesheet does not define, sets a colour that is not
   a token, or has a figure script that uses `fetch`, storage, `document`
   or `window`. It writes nothing until every problem it lists is fixed.
   Fix the problem it names; do not work around it.

4. When the reader asks for changes, edit the pages and run the build again
   with the same output path. The command overwrites a file it built and
   refuses any other file. A tab served over HTTP reloads on its own; a
   file opened from disk needs a manual reload.

## What the skill provides

The skill provides materials and a stylesheet, not a template. The
materials are diagrams rendered by Mermaid, with labels that can carry
markup; code read from the repository, with notes between the lines; diffs
in the Pierre viewer; charts; equations; figures with controls the reader
can move; and prose. Every document uses the shipped stylesheet. A document
that adds its own CSS is unusual and needs a reason.

The skill does not say what a document contains. Most documents open with
a diagram of the subject, but a subject that is better introduced by a
sequence diagram, a chart or a paragraph should open with that. If two
documents look alike, the subject was fitted to a shape instead of being
explained.

## Before handing it over

Open the built file and read it as the reader would. Compare two excerpts
with the real files by eye, even though the build already checked them.
Check every number against the source it came from. Open a diagram in the
lightbox. Switch the theme. If the subject is a change, confirm that the
amber marks are exactly what it touched. Then read every sentence against
the list at the end of writing.md.
