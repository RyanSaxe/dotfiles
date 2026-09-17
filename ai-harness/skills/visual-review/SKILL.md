---
name: visual-review
description: Explore and explain a codebase visually in a browser session mounted on the repository. Use only when the user explicitly invokes visual-review by name, never for ordinary questions about code.
---

# Visual review

Answer questions about a repository with an organized, visual explanation the
user reads in a browser while the real code sits beside it.

The skill starts a local helper mounted on the repository and opens a browser
app. The user asks a question; you plan an outline of pages, then write each
page as Markdown with diagrams, code excerpts, diffs, and notes. Pages appear
as you write them. The user follows references into the real files, selects
lines, and asks again from where they are looking. The session exports to one
HTML file.

This skill is invoked by name. It is not a review tool and posts nothing to
GitHub.
