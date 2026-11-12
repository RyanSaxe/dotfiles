---
name: write-docs
description: Write a README and documentation pages that explain how a project works. Use when creating or rewriting a README, a docs folder or a single documentation page.
---

# Write docs

Apply this guidance when you write or rewrite a README or a documentation page. Use `write-well` and `unslop` for the
prose. This skill adds what is specific to documentation: what belongs on each page, how to lay a page out, how to draw
its diagrams and how to check the result.

## Give each page one question

A reader opens a documentation page with a question. Decide what that question is before you write, and include only
what answers it. A page written around a topic instead collects every fact about that topic, and the reader has to
find the explanation among them.

Suppose you're writing the architecture page for an export service. The service builds CSV files in background jobs.

Original:

> The service has four modules. `api` defines the routes, `jobs` defines the job model, `worker` runs jobs and
> `storage` wraps the file store. Ruff and mypy run before each commit, and CI runs the tests on every push.

Revision:

> `POST /exports` creates a job and returns its ID. A worker takes the job from the queue, builds the CSV file and
> saves it to storage. `GET /exports/{job_id}` returns the job's status and, once the file is saved, its download URL.
> The API never builds a file, so a large export can't make a request time out.

The reader of an architecture page asks how the parts work together. The original names the parts and leaves that
question open. The revision follows one export through the service and gives the reason for the design. The checks
moved to the contributing page, where someone preparing a change looks for them.

These are the usual pages and the question each one answers:

| Page         | Question                                                    |
| ------------ | ----------------------------------------------------------- |
| README       | What can I do with this, and how does it work?              |
| Concept      | How does this part work, and why was it built this way?     |
| Guide        | How do I do this task?                                      |
| Reference    | What exactly is this format, command or field?              |
| Status       | What works today, and what hasn't been built?               |
| Contributing | How do I set up the project and check a change?             |

When a page starts answering a second question, move that material to the page that owns it.

## Write the README about what its reader can do

The reader has just found the project and is deciding whether to use it. They want to know what it does for them and
what using it looks like. Describe the project from their side before you describe how it is built.

1. One or two sentences that say what the reader can do with the project.
2. The main entry point in a code block: the command or the few lines of code a user writes first, with the output
   they get back.
3. How it works: one diagram, followed by the few ideas the design depends on.
4. How to install it.
5. A table of the documentation pages that says what each one explains.
6. The licence.

The code block in part 2 often tells the reader more than any paragraph, because it shows the interface they would
use. Take it from a run of the real project.

Part 3 is the one drafts tend to leave out. Installation steps tell the reader how to run the project. They don't
tell the reader what it does when it runs.

If something the README describes hasn't been built, say so in the sentence that describes it.

## Lay out a page for a reader who skims

Many readers skim a page before deciding to read it, and many read on a phone. Start with one or two sentences that
say what the page explains. Then give them a diagram or a table before the first long passage of prose, so the
structure is visible before the detail.

Keep a page near 500 words and a paragraph under about 50. A longer paragraph usually contains a comparison that
belongs in a table, separate items that belong in a list, or two ideas that each need a paragraph. Keep table cells
to a few words, because a wide table scrolls sideways on a phone.

Show an interface with its signature or a few lines of real use, and link to the source for the implementation. Code
copied into a page goes out of date when the source changes.

Describe only what exists. If something is planned, say that it hasn't been built.

## Draw diagrams as SVG files

A Mermaid block renders only in a client that supports Mermaid, and a syntax error replaces the diagram with an error
message. An SVG file is an image, so it appears wherever images do. Draw each diagram as a light and a dark SVG file
and let the page choose between them with a `<picture>` element.

[Diagrams](references/diagrams.md) has the markup, an SVG template and the layout rules.

## Check the pages as the reader will see them

Markdown that looks correct in an editor can still render wrongly on the site that hosts it. Before you report that
the documentation is finished:

1. Run every command and code example the pages show. Copy the output from that run into the page.
2. Run the script in [Checks](references/checks.md). It reports broken links and image paths, long paragraphs and long
   pages.
3. Open each rendered page on its host, such as GitHub, and look at every diagram.
4. Tell the user which themes and screen sizes you looked at. If you couldn't view a page, say so.

## Read every page another agent drafts

An agent that didn't build the project can describe the code but often can't say why it was designed that way. If you
delegate a draft, read every page of it against this guidance before you publish it. Rewrite the passages that
describe the code without explaining it.
