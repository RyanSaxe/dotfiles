# The frame

## Frame and content

The frame owns the sidebar, the previous and next links at the end of each
page, the bell for other live sessions, Settings (appearance and
notifications), the Feedback page, the working card (the round's steps,
ticked as the agent reports them), and the preview and read-only modes. The
sidebar holds the title, the revision line and its popover, the pages,
Agreed, Feedback with a count of unsent items, and Submit at the foot,
which shows when the last round was sent and becomes Accept plan on a final
plan that can be accepted. The page layout is yours. The frame provides
basic typography, tables, code, theme colors, focus, and selected-choice
states; it provides no generic card or column layouts. The builder wraps
the plan's CSS in `@scope (#page-content)`, so a rule for `body`, `:root`,
or `h1` reaches only the page's content.

The tokens and the type below are the design language of every plan: style
the components a plan makes with them and do not redefine them. Tokens, each
with a light and a dark value: `--ground` (the page behind the
frame, panels, and figure grounds), `--panel` (the frame, cards, popovers),
`--line` and `--line-strong`, `--ink`, `--muted`, `--accent` with
`--accent-ink` and `--accent-soft`, `--attention` and `--attention-bg`
(needs you), `--ok` and `--ok-bg` (sent, accepted), `--danger` and
`--danger-bg` (removed), `--code`, and `--mark` (noted text). Do not color
preferred options green or alternatives red to express preference, and add
labels so that meaning never rests on color alone.

Type is the system stack: 13px chrome, 13.5px to 15px reading, 22px page
titles, uppercase 10.5px labels. Radii are 10px for cards, 7px for buttons,
6px for rows. The frame is at most 1160px wide and centered; the reading
column is at most 820px.

Frame popups close on an outside click or Escape without submitting
anything. Custom popups should do the same and keep unsent text. Single
keys, listed under `?`, move between sessions, pages, and interactive
items, and `s` focuses Submit so that Enter sends. Keep authored controls
focusable so the keys reach them.

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
only Submit sends it. Keep control IDs and labels the same across
revisions. Group IDs must be unique within a page across all kinds, and
option IDs within a group. Use native buttons for single choices, native
labeled checkboxes for checklists, and a textarea inside `data-question`
for answers.

Every checklist travels with a submission, including lists on pages the
user has not visited, so put checklist markup in the page HTML instead of
adding it from a script. Authored `checked` attributes set the initial
values; saved draft values take precedence. A list counts as one unsent
item once the user has changed a box, even if they put it back. An
untouched list is sent with `touched: false` and listed on Feedback as a
default afterwards. An empty set means "None selected", not unanswered.

Register custom initialization on `plan:page`. The custom JS file runs
before the frame module. Script elements inside page HTML do not execute.
Page-level and text-selection comments need no custom code.

Noted text is highlighted. Hovering it shows the note, and clicking opens
the note to edit. The count of notes on a page sits at the bottom, above
the page actions. The Feedback page groups items by page, with edit and
remove, and holds the overall comment. Submit, at the foot of the sidebar,
sends everything unsent at once. Sent items stay listed as sent until the
next revision; items whose page or text no longer exists are listed under
the revision they came from. A submission carries `groups.choices`
(checklists with `touched`), `groups.notes`, and, when present,
`groups.answers` keyed `page/question` with `label`, `text`, and `topic`.
Its text lists untouched checklists after "Defaults, not confirmed:".

## Renderers and figures

Use the renderer that matches the content. Load only what the page needs.

| Content                                | Markup contract                                                       | Renderer |
| -------------------------------------- | --------------------------------------------------------------------- | -------- |
| Source code                            | data-language set to the actual language; HTML-escaped source as text | Shiki    |
| Inline or display math                 | data-math set to inline or display; source as text                    | KaTeX    |
| Diagrams                               | data-diagram with Mermaid source as text                              | Mermaid  |
| Charts and mathematical demonstrations | data-chart with an ECharts option object as JSON text                 | ECharts  |

`data-file` on a code block adds a header with the file name, the language,
and a Copy button. `data-caption` on code, diagrams, and charts adds a
caption line. `data-title` on a chart adds a header. A diagram renders at
its drawn size and scrolls sideways when it is wider than the column,
shrinks to its column inside a side-by-side layout, and opens full size on
a click. Flowcharts use rank spacing 36, node spacing 28, and a title
margin of 8. The Diagrams section of the component index says what keeps a
diagram legible. Use the code renderer for source code, never a bare
block, and the [diff component](../components/index.md) for before and
after. Language grammars load on demand; an unsupported language keeps its
source and reports the failure. Escape backslashes again when math is
stored inside a JSON string.

The frame owns the pinned CDN locations and integrity values, so rendering
needs a network connection. Native SVG and custom components are still
allowed when they communicate an idea better.
