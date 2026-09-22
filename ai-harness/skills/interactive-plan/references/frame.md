# Frame behavior

## Frame and content

The frame provides the header, sidebar, previous and next links, the bell,
Settings, the Feedback page, the working card and preview and read-only
modes. The bell lists other live sessions and closes them. The working card
lists the round's steps and ticks them as the agent reports progress. The
header spans the frame at every width. It displays the revision clock,
Settings and the bell on the left, and Submit on the right. Submit changes to
Accept plan for a final plan and becomes disabled after the agent
sends a round. The clock opens a dialog that lists every revision, newest
first, and ticks the current revision. Selecting a revision opens it. Below
720px, a menu button replaces the sidebar and opens the same page list in a
dialog. The sidebar lists Agreed, the pages and Review comments. Review
comments opens the Feedback page and displays the count of unsent items. The
browser tab displays the plan title. The revision dialog displays it under
the current revision. Page HTML starts below the title and must not contain
an `h1`. The build rejects a page that contains one. The page controls its own
layout. The frame provides basic typography, tables, code, theme colors,
focus and selected-choice states. It does not provide generic card or column
layouts.
The builder wraps the plan's CSS in `@scope (#page-content)`, so a rule for
`body`, `:root`, or `h1` reaches only the page's content.

The tokens and type below are shared design tokens for every plan. Style
the components a plan makes with them and do not redefine them. Tokens, each
with a light and a dark value: `--ground` (the page behind the frame,
panels, and figure grounds), `--panel` (the frame, cards, popovers),
`--line` and `--line-strong`, `--ink`, `--muted`, `--accent` with
`--accent-ink` and `--accent-soft`, `--attention` and `--attention-bg`
(needs you), `--ok` and `--ok-bg` (sent, accepted), `--danger` and
`--danger-bg` (removed), `--code`, and `--mark` (noted text). Do not color
preferred options green or alternatives red to express preference, and add a
label wherever color is the only sign of a meaning.

Type is the system stack: 13px chrome, 13.5px to 15px reading, 22px page
titles, uppercase 10.5px labels. Radii are 10px for cards, 7px for buttons,
6px for rows. The frame is at most 1160px wide and centered, and the reading
column is at most 780px of text.

The frame is exactly as tall as the visible window. The browser scrolls the
page inside the frame, so the window itself never scrolls and content does not
pass under the header. The session stores the page and scroll offset, so the
bell can return the reader to the same place after a jump to another session.
The session record stores the revision. A new revision opens at the top of its
first page, and the frame ignores a page that the revision no longer has.
Reading an older revision draws a strip under the header that names it and
links back to the current one. Frame dialogs close on Escape or their ✕ without
submitting anything, and each takes the focus on its own heading so no
control is left ringed. Custom popups do the same and keep unsent text.
Single keys, listed under `?`, move between sessions and pages, `j` and `k`
choose the next and previous block so that `c` comments on it, and `s`
focuses Submit so that Enter sends. Tab reaches the controls inside a block,
so keep authored controls focusable.

## Choices, comments, and answers

| Interface                            | Behavior                                                                                                                                                                                                                                           |
| ------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| data-choice                          | Stable choice-group ID. Use data-label for a readable label.                                                                                                                                                                                       |
| data-multiselect                     | Stable checklist-group ID. Use data-label for a readable question or group label.                                                                                                                                                                  |
| data-question                        | Stable question ID on a section with a textarea. Use data-label for the answer's label.                                                                                                                                                            |
| data-value                           | Stable option ID on a button in data-choice, or a native checkbox in data-multiselect.                                                                                                                                                             |
| data-label on an option              | Readable option label, separate from its ID and action text. The build refuses one over 24 characters, which is what a tab strip fits. A group's data-label has no limit. Buttons fall back to their text, and checkboxes fall back to data-value. |
| data-kind on a block                 | The word the comment control uses for this block, after "this". A component sets it on its own root. The frame names any other block from its contents.                                                                                            |
| aria-pressed                         | Set by the frame to reflect the draft selection.                                                                                                                                                                                                   |
| data-comment                         | Button action for a contextual note, using the attribute as its label. The nearest ancestor ID becomes the note's target.                                                                                                                          |
| planUI.comment(anchor, quote)        | Open a contextual comment from a custom control.                                                                                                                                                                                                   |
| plan:page                            | Window event after each page render. detail has page and element.                                                                                                                                                                                  |
| planUI.enhance(element)              | Render rich content added dynamically.                                                                                                                                                                                                             |
| planUI.chart(element, options)       | Return an ECharts instance asynchronously.                                                                                                                                                                                                         |
| planUI.diff(element, input, options) | Render one Git file patch through Pierre. Input contains before, after, and patch strings. options.diffStyle is split or unified.                                                                                                                  |
| planUI.prefs.get(key), set(key, v)   | Remember a viewing preference for this session and artifact in the browser.                                                                                                                                                                        |
| planUI.mode                          | live, readonly, or preview.                                                                                                                                                                                                                        |

Choice clicks, checklist changes, and typed answers update the local
draft. Only Submit sends it. Keep control IDs and labels the same across
revisions. Group IDs must be unique within a page across all kinds, and
option IDs within a group. Use native buttons for single choices, native
labeled checkboxes for checklists, and a textarea inside `data-question`
for answers.

Include every checklist in a submission, including lists on pages the user
has not visited. Put checklist markup in the page HTML instead of adding it
from a script. Authored `checked` attributes set the initial values, and the
scope-checklist component sets none. The agent therefore reads the reviewer's
selection rather than an authored default. Saved draft values take precedence.
A list counts as one unsent item once the user has changed a box, even if
they put it back. An
untouched list is sent with `touched: false` and listed on Feedback as a
default afterwards. An empty set means "None selected", not unanswered.

Register custom initialization on `plan:page`. The custom JS file runs
before the frame module. Script elements inside page HTML do not execute.
Page-level, block and text-selection comments need no custom code. One
control sits at the bottom right at every width and names what it will
comment on: the selection while there is one, otherwise the block the reader
last clicked, otherwise the page. Pressing it opens the note dialog on that
target, and the note continues to target that block. Clicking a block that is
not a paragraph, heading or list chooses it and draws a bar in the column's
left padding beside it. Clicking the same block again, clicking elsewhere on
the page, or pressing Escape clears the choice. The control names the block
by what it is, so a decision reads "Comment on this decision" and a table
"Comment on this table". A component names itself with `data-kind`.
If a block has no `data-kind`, the frame displays "Comment on this block".
The note is filed under the name the block gives, its heading,
`data-title`, `data-file`, figure title or caption. If a block names none
of those, use the heading above it, then its type. If another block on the
page has the same name, number the names so every Feedback note identifies
its block. A note on a block adds a muted bar to the block's left padding.
The accent
marks the block the reader is about to comment on. The muted bar marks a
block that already has notes.

Noted text is highlighted. Hovering it shows the note, and clicking opens
the note to edit. The count of notes on a page sits at the bottom. The
Feedback page groups items by page and includes edit, remove and the
overall comment. Submit, at the right of the header, sends everything unsent
at once and displays the count while items wait. Sent items stay listed
as sent until the next revision. An item whose page or text no longer exists
is listed under the revision it came from. A submission includes
`groups.choices` (checklists with `touched`), `groups.notes` and, when
present, `groups.answers` keyed `page/question` with `label`, `text`, and
`topic`. Its text lists untouched checklists after "Defaults, not
confirmed:".

## Renderers and figures

Use the renderer that matches the content. Load only what the page needs.

| Content                                | Markup contract                                                          | Renderer |
| -------------------------------------- | ------------------------------------------------------------------------ | -------- |
| Source code                            | data-language set to the actual language, and the source as escaped text | Shiki    |
| Inline or display math                 | data-math set to inline or display, and the source as text               | KaTeX    |
| Diagrams                               | data-diagram with Mermaid source as text                                 | Mermaid  |
| Charts and mathematical demonstrations | data-chart with an ECharts option object as JSON text                    | ECharts  |

`data-file` on a code block adds a header with the file name, the language and
a Copy button. Four more attributes identify parts of a figure:

| Attribute    | On                | What the frame does with it                                                                                                        |
| ------------ | ----------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| data-lines   | `[data-language]` | `"3-4"` or `"7"`. Numbers the lines, lights the range, and dims the rest until the pointer or the keyboard is on the block.        |
| data-numbers | `[data-language]` | `"true"`. Numbers the lines and dims nothing.                                                                                      |
| data-notes   | `[data-language]` | `[{"line": 3, "text": "…"}]`. A speech bubble in the gutter of each named line, opening the note in a popover. Needs no range.     |
| data-terms   | `[data-math]`     | `[{"symbol": "t", "meaning": "…", "value": "8 s"}]`. Names the formula's coloured terms under it, in the order the colours appear. |

A term takes its colour from a literal in the source, because KaTeX runs
with no `trust` option and refuses `\htmlClass`: write
`\textcolor{#1d4ed8}`, `\textcolor{#a16207}`, `\textcolor{#047857}` or
`\textcolor{#9333ea}` and the frame swaps the literal for the class that
follows the theme. Those four are a content palette, separate from
`--accent`, `--ok`, `--attention` and `--danger`, which indicate state in the
chrome. A block that scrolls sideways fades its right edge while content
remains off-screen. `data-caption` on code, diagrams and charts adds a
caption line. `data-title` on a chart adds a header. A diagram renders at
its drawn size and scrolls sideways when it is wider than the column. It
scales to the column inside a side-by-side layout. Clicking a diagram opens it
full size. Flowcharts use rank spacing 36, node spacing 28 and a title margin
of 8. The Diagrams section of the component index explains how to keep diagrams
legible. Use the code renderer for source code, never a bare block, and the
[diff component](../components/index.md) for before and after. Language
grammars load on demand. If a language is unsupported, the renderer displays
the source and reports the failure. Escape backslashes again when math is
stored inside a JSON string.

The frame defines the pinned CDN locations and integrity values, so rendering
needs a network connection. Native SVG and custom components are still
allowed when they present the content more clearly.
