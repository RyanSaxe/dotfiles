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
| title      | Human-readable artifact title.                                            |
| pages      | Ordered records with unique id, title, and html, or file instead of html. |
| css, js    | Optional paths to custom files, relative to the manifest.                 |
| agreements | Optional structured agreement records.                                    |
| prototypes | Optional preserved, self-contained interactive documents.                 |

Final plans begin with page ID `overview`; remaining pages contain implementation
steps. `feedback` is reserved; `agreed` is reserved when structured agreements
are present. Preserve page IDs across revisions.

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
| title  | Accessible, descriptive title.                                           |
| html   | Complete self-contained HTML document, including its styles and scripts. |
| file   | Manifest-only alternative to html; resolved relative to the manifest.    |
| height | Positive preview height in pixels.                                       |

Put `data-prototype="ID"` on an element where that prototype belongs. The frame
renders the document in a sandboxed iframe and offers its exact source with syntax
highlighting. The same stored HTML supplies both views. It has no same-origin
access to the review frame; its buttons must not submit real session feedback.
Scripts, forms, and popup links are allowed within the sandbox.

Preserve approved visuals and interactions in the relevant final-plan step,
alongside binding requirements and any accepted changes. Clearly label
illustrative content and unfinished integration work. Keep accepted code and
interfaces verbatim in language-marked elements when they do not need a prototype.

Embed essential local images and resources. Do not depend on a temporary file or
earlier server for the specification. External rendering must have an adequate
source or visual fallback. Exercise the embedded version, then extract and open
its source independently. Assembly must not silently redesign approved work.

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
to fill the record. Remove old change markers on the next publication. The index
previews the agreement text; the detail pane retains its full content.

Each source reference has a `kind`:

| kind         | Required fields        | Meaning                                                                      |
| ------------ | ---------------------- | ---------------------------------------------------------------------------- |
| note         | submissionId, noteId   | Exact saved comment and its original quote/context.                          |
| choice       | submissionId, choiceId | Exact selected value and label; choiceId is the submission's choice-map key. |
| conversation | text                   | Agent-provided conversation context, explicitly labeled.                     |

Several references can support one agreement. The publisher resolves browser
references from this session's saved submissions and embeds `sourceRecords`
before hashing the artifact. Do not author resolved records; publication replaces
them. Missing submissions or items fail publication.

Source records include exact text and context, with links to immutable original
proposals. They remain readable offline. New choices carry stable target IDs;
older submissions may link only to a page. Conversation references do not imply
access to a transcript or require an invented browser link.

A valid source does not prove that the summary is correct. Read feedback and
conversation context before changing the agreement. A recommendation is not an
agreement. Entry notes carry agreement identity through the normal draft and
submission flow; they do not change state automatically.

## Frame and content

Keep the shared navigation, orientation, Settings, status footer, and review
controls. The page layout is yours to compose. Basic typography, tables, code,
theme colors, focus, and selected-choice states are available. There are no
generic card or column layouts to fill.

Blue is the general accent. Success, danger, and attention have theme tokens
`--success`, `--danger`, and `--attention`, with background and border variants.
Do not color preferred options green or alternatives red merely to express
preference. Include labels so meaning does not rely on color.

Appearance follows the system until explicitly selected, remembered across local
ports. Drafts stay revision- and session-scoped. Status reports the helper's last
declared state, not an agent heartbeat or invented task progress.

Frame popups dismiss on outside click or Escape without submitting or accepting.
Follow that behavior in custom popups, preserve unsent text, and keep keyboard
focus usable.

## Choices, comments, and custom interactions

| Interface                            | Behavior                                                                                                                          |
| ------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------- |
| data-choice                          | Stable choice-group ID. Use data-label for a readable label.                                                                      |
| data-value                           | Selectable value on a button inside the group.                                                                                    |
| aria-pressed                         | Set by the frame to reflect the draft selection.                                                                                  |
| data-comment                         | Button action for a contextual note, using the attribute as its label.                                                            |
| planUI.comment(anchor, quote)        | Open a contextual comment from a custom control.                                                                                  |
| plan:page                            | Window event after each page render; detail has page and element.                                                                 |
| planUI.enhance(element)              | Render rich content added dynamically.                                                                                            |
| planUI.chart(element, options)       | Return an ECharts instance asynchronously.                                                                                        |
| planUI.diff(element, input, options) | Render one Git file patch through Pierre. Input contains before, after, and patch strings; options.diffStyle is split or unified. |

Choice clicks update the local draft. Only Submit feedback sends it. Keep control
IDs and labels stable. The frame supplies missing choice target IDs for source
links. Use native buttons for accessible selection; style and position them with
the material being compared.

Register custom initialization on `plan:page`. The custom JS file executes before
the frame module. Script elements inserted inside page HTML do not execute.
Page-level and text-selection comments require no custom code.

Feedback supports topic, item, and overall comments, edits, removal, context links,
and explicit submission. Every topic has a section with an Add comment control,
including topics without feedback. Settings is beside Review & submit in the
header. Receipt and acknowledgement stay beside Submit.
Do not build a second feedback transport.

## Renderers

Use the renderer matching the content. Load only what the page needs.

| Content                                | Markup contract                                                       | Renderer |
| -------------------------------------- | --------------------------------------------------------------------- | -------- |
| Source code                            | data-language set to the actual language; HTML-escaped source as text | Shiki    |
| Inline or display math                 | data-math set to inline or display; source as text                    | KaTeX    |
| Diagrams                               | data-diagram with Mermaid source as text                              | Mermaid  |
| Charts and mathematical demonstrations | data-chart with an ECharts option object as JSON text                 | ECharts  |

Use the code renderer for source code instead of bare unhighlighted blocks.
For before/after code, use the [diff component](../components/index.md).
Its pinned viewer uses the frame's Shiki theme pair and follows Settings.
Language grammars load on demand; unsupported languages retain source and report
failure. Escape backslashes again when math is stored inside a JSON string.

The frame owns pinned CDN locations and integrity values. ESM dependency graphs
are not fully integrity-verified by version pinning. CDN rendering needs a
connection. Native SVG and custom components remain available when they
communicate an idea better.

## Before publication

Use available formatting and lint tools on authored files. Inspect the page in
the actual browser, including meaningful choices, comments, popups, renderers,
themes, and narrower layouts. Check source fallback. Do not repeat an unrelated
capability matrix for every prose edit.

For final plans, inspect the preserved approved work and extract its source from
plan-data. The plan and project must be enough to implement the work. Source
records and links to old proposals cannot replace the approved material itself.
