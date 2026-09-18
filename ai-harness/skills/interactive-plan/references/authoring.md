# Author browser artifacts

Author HTML pages and a JSON manifest in the session directory, with custom
CSS and JavaScript as needed, and build one artifact from them:

```sh
node scripts/build.mjs SOURCE.json ARTIFACT.html
```

The output filename must be new. Build into a directory of your own under
the session directory, such as `src/out/`; the publisher owns `artifacts/`
and refuses a name that already exists there. The builder embeds the frame
and the authored content into one HTML file; it does not bundle imports or
linked files, so embed every local resource the plan needs. Do not modify shared skill assets
for a particular plan, and do not install packages to author one.

## Manifest

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

Final plans begin with page ID `overview`; the remaining pages are the
implementation steps. `feedback` is reserved; `agreed` is reserved when
agreements are present. Preserve page IDs across revisions: unsent draft items
carry over to the next revision by page ID and anchor.

The embedded `plan-data` JSON holds page HTML, agreement records, and
prototype source. Page HTML is trusted authored markup, not Markdown. User
comments are plain text; never inject them into executable HTML or
JavaScript. The builder escapes literal less-than characters in embedded JSON;
keep that escaping when editing an assembled artifact. Leave `session-config`
for the publisher to fill, and never put the agent token in the page.

## Prototypes

A prototype preserves an approved interaction verbatim, so the implementer
sees the behavior instead of a description of it.

| Field  | Contract                                                                 |
| ------ | ------------------------------------------------------------------------ |
| id     | Unique stable ID with the same character rules as page IDs.              |
| title  | Accessible, descriptive title, shown in the embed's header.              |
| html   | Complete self-contained HTML document, including its styles and scripts. |
| file   | Manifest-only alternative to html; resolved relative to the manifest.    |
| height | Positive preview height in pixels.                                       |

Put `data-prototype="ID"` on an element where the prototype belongs. The frame
renders it framed: a header with the title, a Source toggle that shows the
exact source with syntax highlighting, and Open full size, which shows the
document alone in a new tab. The document runs in a sandboxed iframe with no
same-origin access to the review frame, so its controls cannot submit real
feedback; scripts, forms, and popup links work inside the sandbox. The embed
is transparent: the document paints its own ground and should follow the
viewer's theme with a `prefers-color-scheme` rule.

An embed is about 780px wide. A component mock renders at its natural width
and reads as it is. A layout mock designed wider than the embed collapses
unless it scales: give it a stage at the design width (1120 works for a
three-column layout) with `transform: scale(min(1, innerWidth / 1120))`,
a control to switch to 100%, and rely on Open full size as the way to see
it real.

Browser automation cannot capture a sandboxed embed: a screenshot of the
review page shows the frame around a blank iframe. Verify a prototype
through Open full size, or serve its file directly.

## Agreements

| Field       | Contract                                                                                     |
| ----------- | -------------------------------------------------------------------------------------------- |
| id          | Unique stable agreement ID, preserved when the topic changes.                                |
| title, html | Concise title and the actual agreement, with exact details as needed.                        |
| state       | agreed by default; reopened retains prior wording until resolved; retired includes a reason. |
| change      | Optional new or updated marker for this publication only.                                    |
| sourceRefs  | One or more references to the material that supports the agreement.                          |

Each reference has a `kind`:

| kind         | Required fields        | Meaning                                                                           |
| ------------ | ---------------------- | --------------------------------------------------------------------------------- |
| note         | submissionId, noteId   | A saved comment, with its quote and target.                                       |
| choice       | submissionId, choiceId | A saved choice; choiceId is the submission's choice-map key.                      |
| answer       | submissionId, answerId | A saved answer to a question component; answerId is the submission's answers key. |
| conversation | text                   | Context from the agent conversation, labeled as such.                             |

Publication resolves browser references from this session's saved
submissions, embeds the exact text and location as `sourceRecords`, and fails
when a submission or item is missing. Do not author `sourceRecords`. Remove
old `change` markers on the next publication, and do not recreate settled
entries to fill the record.

Agreed renders each agreement as a card: the decision, then a strip naming
the revision and the note, choice, or answer it came from, with Preview and
Open. Preview expands that revision's page inside the card, scrolled to the
source and highlighted; Open shows the revision read-only. Further sources
sit behind a count on the strip.

The card's strip, Preview, and Open show the first browser source in
`sourceRefs`. If agreed material changes in a later revision, update the
agreement: mark it `change: updated`, rewrite its text, and list the newest
source first. Otherwise Preview keeps opening the old version.

A valid source does not make the summary correct: read the feedback and the
conversation before writing or changing an agreement. Comments the user
leaves on a card carry the agreement's ID with them and change nothing on
their own.

## Frame and content

The frame owns the sidebar (title, revision line and popover, pages, Agreed,
Feedback with a count of unsent items, and Submit at the foot, which reads
when the last round went or becomes Accept plan on an acceptable final plan),
the previous and next links at the end of each page, the bell for other live
sessions, Settings (appearance and notifications), the Feedback page, the
working card (the round's steps, ticked as the agent reports them), and the
preview and read-only modes. The page layout is yours. Basic typography, tables, code,
theme colors, focus, and selected-choice states are provided; there are no
generic card or column layouts to fill.

Tokens, each with a light and a dark value: `--ground` (the page behind the
frame, panels, and figure grounds), `--panel` (the frame, cards, popovers),
`--line` and `--line-strong`, `--ink`, `--muted`, `--accent` with
`--accent-ink` and `--accent-soft`, `--attention` and `--attention-bg` (needs
you), `--ok` and `--ok-bg` (sent, accepted), `--danger` and `--danger-bg`
(removed), `--code`, and `--mark` (noted text). Do not color preferred
options green or alternatives red to express preference, and include labels so
meaning never rests on color alone.

Type is the system stack: 13px chrome, 13.5px to 15px reading, 22px page
titles, uppercase 10.5px labels. Radii are 10px for cards, 7px for buttons,
6px for rows. The frame is at most 1160px wide and centered; the reading
column is at most 820px.

Frame popups close on an outside click or Escape without submitting anything.
Custom popups should do the same and keep unsent text. Single keys, listed
under `?`, move between sessions, pages, and interactive items, and `s`
focuses Submit so Enter sends; keep authored controls focusable so they take
part.

## Choices, comments, and answers

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

Choice clicks, checklist changes, and typed answers update the local draft;
only Submit sends it. Keep control IDs and labels stable. Group IDs must be
unique within a page across all kinds, and option IDs within a group. Use
native buttons for single choices, native labeled checkboxes for checklists,
and a textarea inside `data-question` for answers.

Every checklist travels with a submission, including lists on pages the user
has not visited, so put checklist markup in page HTML rather than adding it
from script. Authored `checked` attributes set initial values; saved draft
values take precedence. A list counts as one unsent item once the user
changed a box, even if put back; an untouched list is sent with
`touched: false` and listed on Feedback as a default afterwards. An empty set
means "None selected", not unanswered.

Register custom initialization on `plan:page`. The custom JS file runs before
the frame module. Script elements inside page HTML do not execute. Page-level
and text-selection comments need no custom code.

Noted text is highlighted; hovering it shows the note, and clicking opens the
note to edit. The count of notes on a page sits at the bottom, above the page
actions. Feedback groups items by page with edit and remove and holds the
overall comment; Submit, at the foot of the sidebar, sends everything unsent
at once. Sent items stay listed as sent until the next revision; items whose
page or text no longer exists are listed under the revision they came from.
Submissions carry `groups.choices` (checklists with `touched`),
`groups.notes`, and, when present, `groups.answers` keyed `page/question`
with `label`, `text`, and `topic`; the text lists untouched checklists
after "Defaults, not confirmed:".

## Renderers and figures

Use the renderer that matches the content. Load only what the page needs.

| Content                                | Markup contract                                                       | Renderer |
| -------------------------------------- | --------------------------------------------------------------------- | -------- |
| Source code                            | data-language set to the actual language; HTML-escaped source as text | Shiki    |
| Inline or display math                 | data-math set to inline or display; source as text                    | KaTeX    |
| Diagrams                               | data-diagram with Mermaid source as text                              | Mermaid  |
| Charts and mathematical demonstrations | data-chart with an ECharts option object as JSON text                 | ECharts  |

`data-file` on a code block adds a header with the file name, the language,
and a Copy button; `data-caption` on code, diagrams, and charts adds a caption
line; `data-title` on a chart adds a header. A diagram renders at its drawn
size and scrolls sideways when wider than the column, shrinks to its column
inside a side-by-side layout, and opens full size on a click; flowcharts use
rank spacing 36, node spacing 28, and a title margin of 8. The component
index's Diagrams section says what keeps one legible. Use the code renderer for source
code, never a bare block, and the [diff component](../components/index.md)
for before and after. Language grammars load on demand; unsupported languages
keep their source and report the failure. Escape backslashes again when math
is stored inside a JSON string.

The frame owns the pinned CDN locations and integrity values; rendering needs
a connection. Native SVG and custom components remain available when they
communicate an idea better.

## Before publication

Build the artifact and inspect its source: choice IDs and labels, feedback
hooks, embedded resources, renderer fallbacks. Use formatting and lint tools
when they are already available; do not install tooling to author a plan
unless asked.
