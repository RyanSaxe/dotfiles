---
name: visual-review
description: Explain a subject in a repository as one self-contained HTML document a reader opens in a browser, built around diagrams, real code and diffs, with pages for a complicated subject. Use only when the user explicitly invokes visual-review by name, never for ordinary questions about code.
---

# Visual review

Make something understood: a pull request, a repository the reader has
never opened, one subsystem, a model with mathematics in it. The output is
one HTML file, opened when it is written and rewritten when the reader
asks again. It is not code review and it posts nothing anywhere.

## The loop

1. Read the repository until you can explain the subject to someone who
   has never opened it. Decide what the subject needs: which parts, which
   diagrams, which lines, which changes, whether an equation or a chart
   would say it better than a paragraph.
2. Write `document.json` and one file per page, in a working directory
   outside the repository's history. [authoring.md](references/authoring.md)
   is the description format and the materials; read it before writing.
   [writing.md](references/writing.md) is what a good document says, and
   [components](components/index.md) are the same contracts as files to
   copy.
3. Build and open it. `SKILL` is this skill's directory and `WORK` the
   working directory; run the build from inside the repository, or set
   `repository` in the description, because the code an excerpt quotes
   comes through Git at the document's `ref`.

   ```sh
   node SKILL/scripts/build.mjs WORK/document.json WORK/out/NAME.html
   open WORK/out/NAME.html
   ```

   The build refuses a document that quotes lines the repository does not
   have, puts a note outside its excerpt, marks a node that does not
   exist, paints a label with a class nothing styles, sets a colour that
   is not a token, or carries a script that reaches outside its figure. It
   writes nothing until every problem it names is fixed; fix the problem,
   do not work around it.

4. When the reader asks again, rewrite what changed and build to the same
   path; the builder overwrites a document it wrote and nothing else. A
   tab served over HTTP reloads on its own; opened from the filesystem,
   the reader presses reload.

## What the skill supplies

Materials and a house style, not a template. Diagrams through Mermaid on
the shipped stylesheet, with labels that carry markup. Code read from the
repository with notes interleaved. Diffs in a real viewer. Charts,
equations, and controls a reader can move. Prose. Every document uses the
shipped stylesheet as it is; reaching for CSS on an ordinary document is
the failure case.

Nothing here says what a document contains. A document usually opens with
a diagram of the subject, and that is a default, not a rule. A subject
whose best opening is a sequence diagram, a chart, or a paragraph gets that
instead. Two documents that look like each other are a sign the subject
was fitted to a shape rather than explained.

## Before handing it over

Open the built file and read it as the reader would. Check two quoted
blocks against the real files by eye even though the build already did.
Check every number against the source it came from. Open a diagram full
size. Switch the theme. If the subject is a change, confirm the marks are
exactly what it touched.
