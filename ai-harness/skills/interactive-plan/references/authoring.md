# Author browser artifacts

Author HTML pages and a JSON manifest in the session directory. Add custom CSS
and JavaScript as needed. Build with
`node scripts/build.mjs SOURCE.json ARTIFACT.html`; the output filename must be new.

The builder embeds the frame and authored content into one HTML artifact. Do not
modify shared skill assets for a particular plan. Embed required local resources;
the builder does not bundle imports or linked files. Do not install packages to
author a plan.

## Manifest and handoff

| Field      | Contract                                                                  |
| ---------- | ------------------------------------------------------------------------- |
| artifactId | Stable artifact ID, using letters, digits, underscores, or hyphens.       |
| revision   | New value for each publication; also allows periods.                      |
| kind       | exploration for proposals; plan for the complete final handoff.           |
| title      | Human-readable artifact title, shown once at the top of the sidebar.      |
| pages      | Ordered records with unique id, title, and html, or file instead of html. |
| css, js    | Optional paths to custom files, relative to the manifest.                 |
| agreements | Optional structured agreement records.                                    |
| prototypes | Optional preserved, self-contained interactive documents.                 |

Final plans begin with page ID `overview`; remaining pages contain implementation
steps. `feedback` is reserved; `agreed` is reserved when structured agreements
are present. Preserve page IDs across revisions: unsent draft items carry over
to the next revision by page ID and anchor.

The embedded `plan-data` JSON contains page HTML, agreement records, and prototype
source. Page HTML is trusted authored markup, not Markdown. User comments are
plain text. Never inject user feedback into executable HTML or JavaScript.

The builder escapes literal less-than characters in embedded JSON. Keep that
escaping when editing assembled artifacts. Leave `session-config` for the
publisher to fill; never put the agent token in the page.

Custom CSS and JS files are embedded separately from plan-data. If an approved
interaction is part of the specification, preserve a complete prototype document
rather than expecting a reader to reconstruct its source from the outer frame.

## Preserved prototypes

Each `prototypes` record has:

| Field  | Contract                                                                 |
| ------ | ------------------------------------------------------------------------ |
| id     | Unique stable ID with the same character rules as page IDs.              |
| title  | Accessible, descriptive title, shown in the embed's header.              |
| html   | Complete self-contained HTML document, including its styles and scripts. |
| file   | Manifest-only alternative to html; resolved relative to the manifest.    |
| height | Positive preview height in pixels.                                       |

Put `data-prototype="ID"` on an element where that prototype belongs. The frame
renders the document framed: a header with the title, a Source toggle that
shows the exact source with syntax highlighting, and Open full size, which
shows the prototype alone in a new tab from the same artifact. The document
runs in a sandboxed iframe with no same-origin access to the review frame; its
buttons must not submit real session feedback. Scripts, forms, and popup links
are allowed within the sandbox.

Preserve approved visuals and interactions in the relevant final-plan step,
alongside binding requirements and any accepted changes. Clearly label
illustrative content and unfinished integration work. Keep accepted code and
interfaces verbatim in language-marked elements when they do not need a prototype.

Embed essential local images and resources. Do not depend on a temporary file or
earlier server for the specification. External rendering must have an adequate
source or visual fallback. Extract the source and check that assembly preserves
the approved work. Use live review to check the embedded version; browser
automation is optional.

## Agreements and exact sources

| Field        | Contract                                                                                     |
| ------------ | -------------------------------------------------------------------------------------------- |
| id           | Unique stable agreement ID, preserved when the topic changes.                                |
| title, html  | Concise title and the actual agreement, with exact details as needed.                        |
| state        | agreed by default; reopened retains prior wording until resolved; retired includes a reason. |
| change       | Optional new or updated marker for this publication only.                                    |
| sourceRefs   | References to the submitted material supporting the agreement.                               |
| source, href | Legacy source note and optional original-page link; still supported.                         |

Supply nonempty sourceRefs or legacy source text. Do not recreate settled entries
to fill the record. Remove old change markers on the next publication.

Agreed renders each agreement as a card: the decision on top, then a strip
naming the revision and the note, choice, or answer it came from, with Preview
and Open. Preview expands that revision's page in preview mode, scrolled to
the source and highlighted, inside the card. Open shows that revision
read-only. Further sources are listed behind a count on the strip.

Each source reference has a `kind`:

| kind         | Required fields        | Meaning                                                                             |
| ------------ | ---------------------- | ----------------------------------------------------------------------------------- |
| note         | submissionId, noteId   | Exact saved comment and its original quote/context.                                 |
| choice       | submissionId, choiceId | Exact choice data and readable labels; choiceId is the submission's choice-map key. |
| answer       | submissionId, answerId | Exact answer to a question component; answerId is the submission's answers key.     |
| conversation | text                   | Agent-provided conversation context, explicitly labeled.                            |

Several references can support one agreement. The publisher resolves browser
references from this session's saved submissions and embeds `sourceRecords`
before hashing the artifact. Do not author resolved records; publication replaces
them. Missing submissions or items fail publication.

Source records include exact text and context, the source revision, and the
target element and quote used for Preview and Open. They remain readable
offline. Conversation references do not imply access to a transcript or
require an invented browser link.

Choice sources retain the submitted record in `choice`. Single choices carry
`value` and `valueLabel`; legacy records display `value`. Checklists carry
`kind: "multiple"` and the complete `options` array, with each option's `value`,
`label`, and `checked` state. Source text displays selected labels, or
"None selected" for an empty checklist.

A valid source does not prove that the summary is correct. Read feedback and
conversation context before changing the agreement. A recommendation is not an
agreement. Entry notes carry agreement identity through the normal draft and
submission flow; they do not change state automatically.

## Frame and content

The frame owns the sidebar (plan title, revision line and popover, pages,
Agreed, and Feedback with a count of unsent items), the previous and next
links at the end of each page, the bell for other live sessions,
Settings (appearance and notifications), the Feedback page, the working state,
and preview and read-only modes. The page layout is yours to compose. Basic
typography, tables, code, theme colors, focus, and selected-choice states are
available. There are no generic card or column layouts to fill.

Tokens, with light and dark values: `--ground` (sidebar and panels behind
content), `--panel` (content, cards, popovers), `--line` and `--line-strong`,
`--ink`, `--muted`, `--accent` with `--accent-ink` and `--accent-soft`,
`--attention` and `--attention-bg` (needs you), `--ok` and `--ok-bg` (sent,
accepted), `--danger` and `--danger-bg` (removed), `--code`, and `--mark`
(noted text). `--blue`, `--bg`, `--side`, `--soft`, and `--success` remain as
aliases. Do not color preferred options green or alternatives red merely to
express preference. Include labels so meaning does not rely on color.

Type is the system stack: 13px chrome, 13.5px to 15px reading, 22px page
titles, uppercase 10.5px labels. Radii are 10px for cards, 7px for buttons,
6px for rows. Appearance follows the system until explicitly selected, and
the choice is remembered for the hub origin.

Frame popups dismiss on outside click or Escape without submitting or accepting.
Follow that behavior in custom popups, preserve unsent text, and keep keyboard
focus usable. Single keys (listed under `?`) jump between sessions, pages, and
interactive items; keep authored controls focusable so they take part.

## Choices, comments, answers, and custom interactions

| Interface                            | Behavior                                                                                                                          |
| ------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------- |
| data-choice                          | Stable choice-group ID. Use data-label for a readable label.                                                                      |
| data-multiselect                     | Stable checklist-group ID. Use data-label for a readable question or group label.                                                 |
| data-question                        | Stable question ID on a section with a textarea. Use data-label for the answer's label.                                           |
| data-value                           | Stable option ID on a button in data-choice, or a native checkbox in data-multiselect.                                            |
| data-label on an option              | Readable option label, separate from its ID and action text. Buttons fall back to their text; checkboxes fall back to data-value. |
| aria-pressed                         | Set by the frame to reflect the draft selection.                                                                                  |
| data-comment                         | Button action for a contextual note, using the attribute as its label; the nearest ancestor ID becomes the note's target.         |
| planUI.comment(anchor, quote)        | Open a contextual comment from a custom control.                                                                                  |
| plan:page                            | Window event after each page render; detail has page and element.                                                                 |
| planUI.enhance(element)              | Render rich content added dynamically.                                                                                            |
| planUI.chart(element, options)       | Return an ECharts instance asynchronously.                                                                                        |
| planUI.diff(element, input, options) | Render one Git file patch through Pierre. Input contains before, after, and patch strings; options.diffStyle is split or unified. |
| planUI.prefs.get(key), set(key, v)   | Remember a viewing preference for this session and artifact in the browser.                                                       |
| planUI.mode                          | live, readonly, or preview.                                                                                                       |

Choice clicks, checklist changes, and typed answers update the local draft. Only
Submit sends it. Keep control IDs and labels stable. Group IDs must be unique
within a page, across all kinds. Option IDs must be unique within a group. The
frame supplies missing group target IDs for source links. Use native buttons
for single choices, native labeled checkboxes for checklists, and a textarea
inside `data-question` for answers.

Every authored checklist appears in Feedback, including lists on unvisited
pages. Authored `checked` attributes set initial values; saved draft values take
precedence. An empty set means "None selected", not unanswered. Each checklist
counts as one feedback item. Put checklist markup in page HTML so the frame can
discover it before the user visits the page.

Register custom initialization on `plan:page`. The custom JS file executes before
the frame module. Script elements inserted inside page HTML do not execute.
Page-level and text-selection comments require no custom code.

Notes on selected text show as a numbered marker on the noted text and a count
line under the last noted block; the note itself is read on Feedback. Feedback
groups items by page, with edit and remove, an overall comment, and one Submit
that sends everything unsent at once. Sent items stay listed as sent until the
next revision; items whose page or text no longer exists are listed under the
revision they came from. Submissions carry `groups.choices`, `groups.notes`,
and, when present, `groups.answers` keyed `page/question` with `label`,
`text`, and `topic`.

Do not build a second feedback or reply transport.

## Renderers and figures

Use the renderer matching the content. Load only what the page needs.

| Content                                | Markup contract                                                       | Renderer |
| -------------------------------------- | --------------------------------------------------------------------- | -------- |
| Source code                            | data-language set to the actual language; HTML-escaped source as text | Shiki    |
| Inline or display math                 | data-math set to inline or display; source as text                    | KaTeX    |
| Diagrams                               | data-diagram with Mermaid source as text                              | Mermaid  |
| Charts and mathematical demonstrations | data-chart with an ECharts option object as JSON text                 | ECharts  |

Optional figure attributes: `data-file` on a code block adds a header with the
file name, the language, and a Copy button; `data-caption` on code, diagrams,
and charts adds a caption line; `data-title` on a chart adds a header. Use the
code renderer for source code instead of bare unhighlighted blocks. For
before/after code, use the [diff component](../components/index.md). Language
grammars load on demand; unsupported languages retain source and report
failure. Escape backslashes again when math is stored inside a JSON string.

The frame owns pinned CDN locations and integrity values. ESM dependency graphs
are not fully integrity-verified by version pinning. CDN rendering needs a
connection. Native SVG and custom components remain available when they
communicate an idea better.

## Before publication

Build the artifact and inspect its source, including choice IDs and labels,
feedback hooks, embedded resources, and renderer fallbacks. Use formatting and
lint tools when already available; do not install tooling to author a plan unless
asked. Browser automation is optional. Use live review to find and correct
rendering and interaction problems.

For final plans, inspect the preserved approved work and extract its source from
plan-data. The plan and project must be enough to implement the work. Source
records and links to old proposals cannot replace the approved material itself.
